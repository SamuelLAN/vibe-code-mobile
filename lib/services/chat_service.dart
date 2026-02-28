import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../apis/vibe/coding_stream_api.dart';
import '../apis/vibe/transcribe_api.dart';
import '../models/attachment.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/stream_element.dart';
import 'auth_service.dart';
import 'chat_repository.dart';
import 'settings_service.dart';
import 'stream_buffer_processor.dart';

class ChatService extends ChangeNotifier {
  ChatService({
    ChatRepository? repository,
    AuthService? authService,
    SettingsService? settings,
    TranscribeApiClient? transcribeClient,
    CodingStreamApiClient? codingStreamClient,
  })  : _settings = settings,
        _repo = repository ??
            ChatRepository(authService: authService, settings: settings),
        _authService = authService,
        _transcribeClient = transcribeClient ?? TranscribeApiClient(),
        _codingStreamClient = codingStreamClient ?? CodingStreamApiClient();

  final ChatRepository _repo;
  final AuthService? _authService;
  final SettingsService? _settings;
  final TranscribeApiClient _transcribeClient;
  final CodingStreamApiClient _codingStreamClient;
  final Uuid _uuid = const Uuid();
  static const String _defaultProjectName = 'vibe-code-mobile';

  List<Chat> _chats = [];
  Chat? _activeChat;
  List<Message> _messages = [];
  bool _isGenerating = false;
  String? _error;
  Timer? _streamTimer;
  String? _currentFlowId;
  String? _activeGenerationId;
  final Map<String, StreamBufferProcessor> _streamProcessors = {};

  static const int _chatNotFoundErrorCode = 3001;

  List<Chat> get chats => _chats;
  Chat? get activeChat => _activeChat;
  List<Message> get messages => _messages;
  bool get isGenerating => _isGenerating;
  String? get error => _error;

  Future<void> initialize() async {
    await _repo.init();
    await loadChats();
  }

  Future<void> loadChats() async {
    _chats = await _repo.getChats();
    if (_chats.isEmpty) {
      final chat = Chat(
        id: _uuid.v4(),
        title: 'New Chat',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final createdChat = await _repo.createChat(chat);
      _chats = [createdChat];
    }
    await selectChat(_chats.first.id);
  }

  Future<void> refreshChats() async {
    _chats = await _repo.getChats();
    if (_activeChat != null) {
      final activeId = _activeChat!.id;
      _activeChat = _chats.firstWhere((chat) => chat.id == activeId,
          orElse: () => _chats.first);
    }
    notifyListeners();
  }

  Future<void> selectChat(String chatId) async {
    _activeChat = _chats.firstWhere((chat) => chat.id == chatId);
    final detail = await _repo.getChatDetail(chatId);
    if (detail != null) {
      final index = _chats.indexWhere((chat) => chat.id == chatId);
      if (index != -1) {
        detail.lastMessagePreview ??= _chats[index].lastMessagePreview;
        _chats[index] = detail;
      }
      _activeChat = detail;
    }
    _messages = await _repo.getMessages(chatId);
    notifyListeners();
  }

  Future<void> newChat() async {
    final draftChat = Chat(
      id: _uuid.v4(),
      title: 'New Chat',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final createdChat = await _repo.createChat(draftChat);
    _chats.removeWhere((c) => c.id == createdChat.id);
    _chats.insert(0, createdChat);
    await selectChat(createdChat.id);
  }

  Future<void> deleteChat(String chatId) async {
    await _repo.deleteChat(chatId);
    _chats.removeWhere((chat) => chat.id == chatId);
    if (_activeChat?.id == chatId) {
      if (_chats.isEmpty) {
        await newChat();
      } else {
        await selectChat(_chats.first.id);
      }
    }
    notifyListeners();
  }

  Future<void> updateChatTitle(String chatId, String title) async {
    final chat = _chats.firstWhere((c) => c.id == chatId);
    chat.title = title.trim().isEmpty ? chat.title : title.trim();
    chat.updatedAt = DateTime.now();
    await _repo.updateChat(chat);
    await refreshChats();
  }

  Future<void> sendUserMessage(
      String text, List<Attachment> attachments) async {
    if (_activeChat == null) return;
    _error = null;
    await _ensureActiveChatReady();

    final userMessage = Message(
      id: _uuid.v4(),
      chatId: _activeChat!.id,
      role: MessageRole.user,
      content: text.trim(),
      createdAt: DateTime.now(),
      attachments: attachments,
    );
    await _repo.addMessage(userMessage);
    _messages.add(userMessage);

    await _updateChatMeta(_buildPreviewText(text, attachments));
    notifyListeners();

    final result =
        await _generateAssistantResponse(text, attachments: attachments);
    if (result == _GenerationResult.chatMissing) {
      final recreated = await _recoverMissingChat();
      if (recreated) {
        await _generateAssistantResponse(text, attachments: attachments);
      }
    }
  }

  /// 发送语音消息并进行转写
  Future<void> sendVoiceMessage(File audioFile) async {
    if (_activeChat == null) return;
    _error = null;
    await _ensureActiveChatReady();

    debugPrint('[ChatService] 开始处理语音消息, 文件: ${audioFile.path}');

    // æ£æ¥æä»¶æ¯å¦å­å¨
    if (!await audioFile.exists()) {
      debugPrint('[ChatService] 错误: 音频文件不存在');
      return;
    }

    final fileSize = await audioFile.length();
    final fileExt = audioFile.path.split('.').last.toLowerCase();
    final mimeType = _getMimeType(audioFile.path);
    debugPrint('[ChatService] 音频文件信息:');
    debugPrint('[ChatService]   - 路径: ${audioFile.path}');
    debugPrint('[ChatService]   - 大小: $fileSize bytes');
    debugPrint('[ChatService]   - 扩展名: $fileExt');
    debugPrint('[ChatService]   - MIME类型: $mimeType');

    // 验证文件格式（m4a/wav 都可接受）
    if (fileExt != 'wav' && fileExt != 'm4a') {
      debugPrint('[ChatService] 警告: 语音文件扩展名不是常见格式(wav/m4a)，实际: $fileExt');
    }

    // 读取文件头验证格式（仅对 WAV 强制校验 RIFF）
    try {
      final bytes = await audioFile.openRead(0, 12).fold<List<int>>(<int>[],
          (acc, chunk) {
        if (acc.length >= 12) return acc;
        acc.addAll(chunk);
        return acc.length > 12 ? acc.sublist(0, 12) : acc;
      });
      final ascii = bytes
          .map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.')
          .join();
      debugPrint('[ChatService] 文件签名(ascii): $ascii');
      if (fileExt == 'wav' && bytes.length >= 4) {
        final header = String.fromCharCodes(bytes.take(4));
        debugPrint('[ChatService] WAV 文件头: $header (期望 RIFF)');
        if (header != 'RIFF') {
          debugPrint('[ChatService] 警告: WAV 文件头不是 RIFF');
        }
      } else if (fileExt == 'm4a' && bytes.length >= 8) {
        final brand = String.fromCharCodes(bytes.skip(4).take(4));
        debugPrint('[ChatService] M4A 品牌字段(offset4): $brand (常见 ftyp)');
      }
    } catch (e) {
      debugPrint('[ChatService] 无法读取文件头: $e');
    }

    final messageId = _uuid.v4();

    // 创建语音消息，初始状态为转录中
    final attachment = Attachment(
      id: 'voice_${DateTime.now().millisecondsSinceEpoch}',
      path: audioFile.path,
      name: 'Voice Message',
      type: AttachmentType.voice,
      mime: _getMimeType(audioFile.path),
      sizeBytes: audioFile.lengthSync(),
      transcriptionStatus: TranscriptionStatus.loading,
    );

    final userMessage = Message(
      id: messageId,
      chatId: _activeChat!.id,
      role: MessageRole.user,
      content: '[语音消息]', // 初始内容
      createdAt: DateTime.now(),
      attachments: [attachment],
    );

    await _repo.addMessage(userMessage);
    _messages.add(userMessage);
    notifyListeners();

    // 获取 access token
    final accessToken = await _authService?.getValidToken();
    if (accessToken == null) {
      _updateAttachmentStatus(attachment, TranscriptionStatus.error, '认证失败');
      notifyListeners();
      return;
    }

    // 调用转写 API
    final transcribedText = StringBuffer();
    bool isTranscribeComplete = false;

    try {
      await _transcribeClient.transcribeStream(
        audioFile: audioFile,
        accessToken: accessToken,
        logId: messageId,
        onEvent: (event) {
          switch (event.type) {
            case TranscribeEventType.data:
              if (event.data != null) {
                transcribedText.write(event.data);
                // 流式更新消息内容
                _updateMessageContent(messageId, transcribedText.toString());
              }
              break;
            case TranscribeEventType.complete:
              // 输出转写文本到 console
              final finalText = transcribedText.toString();
              debugPrint('===== 语音转写结果 =====');
              debugPrint(finalText);
              debugPrint('=========================');
              _updateAttachmentStatus(
                attachment,
                TranscriptionStatus.completed,
                finalText,
              );
              // 更新消息内容为转写文本
              _updateMessageContent(messageId, finalText);
              isTranscribeComplete = true;
              break;
            case TranscribeEventType.error:
              debugPrint('[ChatService] 转写错误: ${event.error}');
              _updateAttachmentStatus(
                  attachment, TranscriptionStatus.error, event.error);
              break;
          }
        },
      );

      // 转写完成后，调用 AI 回复接口
      final finalText = transcribedText.toString();
      if (isTranscribeComplete && finalText.isNotEmpty) {
        final result = await _generateAssistantResponse(finalText);
        if (result == _GenerationResult.chatMissing) {
          final recreated = await _recoverMissingChat();
          if (recreated) {
            await _generateAssistantResponse(finalText);
          }
        }
      }
    } catch (e) {
      _updateAttachmentStatus(
          attachment, TranscriptionStatus.error, e.toString());
      notifyListeners();
    }
  }

  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      case 'webm':
        return 'audio/webm';
      default:
        return 'audio/mpeg';
    }
  }

  void _updateMessageContent(String messageId, String content) {
    final messageIndex = _messages.indexWhere((m) => m.id == messageId);
    if (messageIndex != -1) {
      _messages[messageIndex].content = content;
      _repo.updateMessage(_messages[messageIndex]);
      notifyListeners();
    }
  }

  void _updateAttachmentStatus(
      Attachment attachment, TranscriptionStatus status, String? text) {
    attachment.transcriptionStatus = status;
    if (text != null) {
      attachment.transcribedText = text;
    }

    // 找到对应的消息并更新
    final messageIndex = _messages.indexWhere(
      (m) => m.attachments.any((a) => a.id == attachment.id),
    );
    if (messageIndex != -1) {
      _repo.updateMessage(_messages[messageIndex]);
    }
    notifyListeners();
  }

  Future<void> retryLastUserMessage() async {
    final lastUser = _messages.lastWhere(
      (msg) => msg.role == MessageRole.user,
      orElse: () => Message(
        id: _uuid.v4(),
        chatId: _activeChat?.id ?? '',
        role: MessageRole.user,
        content: '',
        createdAt: DateTime.now(),
        attachments: [],
      ),
    );
    if (lastUser.content.isEmpty && lastUser.attachments.isEmpty) return;
    final result = await _generateAssistantResponse(
      lastUser.content,
      attachments: lastUser.attachments,
    );
    if (result == _GenerationResult.chatMissing) {
      final recreated = await _recoverMissingChat();
      if (recreated) {
        await _generateAssistantResponse(
          lastUser.content,
          attachments: lastUser.attachments,
        );
      }
    }
  }

  void stopGeneration() {
    _streamTimer?.cancel();
    final stoppingGenerationId = _activeGenerationId;
    _activeGenerationId = null;
    _isGenerating = false;
    final streaming = _messages.lastWhere(
      (msg) => msg.isStreaming,
      orElse: () => Message(
        id: '',
        chatId: '',
        role: MessageRole.assistant,
        content: '',
        createdAt: DateTime.now(),
        attachments: [],
      ),
    );
    if (streaming.id.isNotEmpty) {
      streaming.isStreaming = false;
      _streamProcessors.remove(streaming.id);
      _repo.updateMessage(streaming);
    }
    notifyListeners();

    final flowId = _currentFlowId;
    _currentFlowId = null;
    if (flowId != null && flowId.isNotEmpty && stoppingGenerationId != null) {
      _stopRemoteGeneration(flowId, stoppingGenerationId);
    }
  }

  Future<void> _updateChatMeta(String text) async {
    if (_activeChat == null) return;
    if (_activeChat!.title == 'New Chat') {
      _activeChat!.title =
          text.length > 32 ? '${text.substring(0, 32)}…' : text;
    }
    _activeChat!.updatedAt = DateTime.now();
    _activeChat!.lastMessagePreview =
        text.length > 60 ? '${text.substring(0, 60)}…' : text;
    await _repo.updateChat(_activeChat!);
    await refreshChats();
  }

  Future<_GenerationResult> _generateAssistantResponse(
    String prompt, {
    List<Attachment> attachments = const [],
    bool hasRetriedAuth = false,
  }) async {
    if (_activeChat == null) return _GenerationResult.failed;
    if (_authService == null) {
      await _generateMockAssistantResponse();
      return _GenerationResult.success;
    }

    final assistantMessage = Message(
      id: _uuid.v4(),
      chatId: _activeChat!.id,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime.now(),
      attachments: [],
      isStreaming: true,
    );

    await _repo.addMessage(assistantMessage);
    _messages.add(assistantMessage);
    _streamProcessors[assistantMessage.id] = StreamBufferProcessor();

    _isGenerating = true;
    // Let backend allocate a fresh flow_id per message when chat_id is provided.
    _currentFlowId = null;
    final generationId = _uuid.v4();
    _activeGenerationId = generationId;
    notifyListeners();

    final accessToken = await _authService.getValidToken();
    if (accessToken == null) {
      _finishAssistantStream(
        assistantMessage: assistantMessage,
        generationId: generationId,
        error: '认证失败，请重新登录',
      );
      return _GenerationResult.failed;
    }
    final projectName = await _effectiveProjectName();
    final contentBlocks = await _buildContentBlocks(prompt, attachments);
    final fallbackPrompt = prompt.trim().isNotEmpty ? prompt : '请结合附件内容回答';

    bool chatMissingError = false;
    bool authInvalidError = false;
    await _codingStreamClient.startStream(
      accessToken: accessToken,
      msg: fallbackPrompt,
      content: contentBlocks.isEmpty ? null : contentBlocks,
      mode: 'flash',
      chatId: _activeChat!.id,
      memoryId: _activeChat!.id,
      projectName: projectName,
      onEvent: (event) {
        if (_activeGenerationId != generationId) {
          return;
        }

        if (event.flowId != null && event.flowId!.isNotEmpty) {
          _currentFlowId = event.flowId;
        }

        switch (event.type) {
          case CodingStreamEventType.message:
            final chunk = event.text ?? event.rawData ?? '';
            if (chunk.isEmpty) return;
            assistantMessage.content += chunk;
            _applyStreamChunkToMessage(assistantMessage, chunk);
            _repo.updateMessage(assistantMessage);
            notifyListeners();
            break;
          case CodingStreamEventType.completed:
          case CodingStreamEventType.interrupted:
            _finishAssistantStream(
              assistantMessage: assistantMessage,
              generationId: generationId,
            );
            break;
          case CodingStreamEventType.error:
            if (_isChatNotFoundError(event)) {
              chatMissingError = true;
              _discardAssistantMessage(assistantMessage);
              _isGenerating = false;
              _activeGenerationId = null;
              _currentFlowId = null;
              notifyListeners();
              break;
            }
            if (_isAuthInvalidError(
              event.error,
              rawData: event.rawData,
              extra: event.text,
            )) {
              authInvalidError = true;
              _discardAssistantMessage(assistantMessage);
              _isGenerating = false;
              _activeGenerationId = null;
              _currentFlowId = null;
              notifyListeners();
              break;
            }
            _finishAssistantStream(
              assistantMessage: assistantMessage,
              generationId: generationId,
              error: event.error ?? event.text ?? '生成失败',
            );
            break;
        }
      },
    );

    if (chatMissingError) {
      return _GenerationResult.chatMissing;
    }

    if (authInvalidError) {
      if (!hasRetriedAuth) {
        final refreshed = await _authService.forceRefreshToken();
        if (refreshed) {
          return _generateAssistantResponse(
            prompt,
            attachments: attachments,
            hasRetriedAuth: true,
          );
        }
      }
      _error = '登录状态已过期，请重新登录';
      notifyListeners();
      return _GenerationResult.failed;
    }

    if (_activeGenerationId == generationId) {
      _finishAssistantStream(
        assistantMessage: assistantMessage,
        generationId: generationId,
      );
    }
    return _GenerationResult.success;
  }

  Future<void> _generateMockAssistantResponse() async {
    if (_activeChat == null) return;

    final assistantMessage = Message(
      id: _uuid.v4(),
      chatId: _activeChat!.id,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime.now(),
      attachments: [],
      isStreaming: true,
    );
    await _repo.addMessage(assistantMessage);
    _messages.add(assistantMessage);
    _isGenerating = true;
    notifyListeners();

    const response = 'Here\'s a focused plan for your request:\n\n'
        '1. Clarify scope and success criteria.\n'
        '2. Sketch the UX flow and key screens.\n'
        '3. Define API contracts and Git operations.\n'
        '4. Implement UI + state management.\n'
        '5. Add secure storage, tests, and polish.\n\n'
        'Tell me where you\'d like to drill in next.';

    int index = 0;
    _streamTimer?.cancel();
    _streamTimer = Timer.periodic(const Duration(milliseconds: 24), (timer) {
      if (index >= response.length) {
        timer.cancel();
        assistantMessage.isStreaming = false;
        _isGenerating = false;
        _repo.updateMessage(assistantMessage);
        notifyListeners();
        return;
      }
      assistantMessage.content += response[index];
      index += 1;
      _repo.updateMessage(assistantMessage);
      notifyListeners();
    });
  }

  void _finishAssistantStream({
    required Message assistantMessage,
    required String generationId,
    String? error,
  }) {
    if (_activeGenerationId != generationId) return;

    if (error != null && error.isNotEmpty) {
      _error = error;
      if (assistantMessage.content.trim().isEmpty) {
        assistantMessage.content = 'Error: $error';
      }
    }

    assistantMessage.isStreaming = false;
    _streamProcessors.remove(assistantMessage.id);
    _repo.updateMessage(assistantMessage);

    _isGenerating = false;
    _activeGenerationId = null;
    _currentFlowId = null;
    notifyListeners();
  }

  Future<void> _stopRemoteGeneration(String flowId, String generationId) async {
    final accessToken = await _authService?.getValidToken();
    if (accessToken == null) return;

    try {
      await _codingStreamClient.stopStream(
        accessToken: accessToken,
        flowId: flowId,
      );
    } catch (e) {
      debugPrint('[ChatService] stopGeneration failed for $flowId: $e');
      if (_activeGenerationId == null || _activeGenerationId == generationId) {
        _error = '停止生成失败: $e';
        notifyListeners();
      }
    }
  }

  void _applyStreamChunkToMessage(Message message, String chunk) {
    final processor = _streamProcessors.putIfAbsent(
        message.id, () => StreamBufferProcessor());
    final newElements = processor.processChunk(chunk);
    if (newElements.isEmpty) return;

    for (final element in newElements) {
      _mergeStreamElement(message.streamElements, element);
    }
  }

  Future<String> _effectiveProjectName() async {
    final selected = await _settings?.getSelectedProjectName();
    if (selected != null && selected.trim().isNotEmpty) {
      return selected.trim();
    }
    return _defaultProjectName;
  }

  String _buildPreviewText(String text, List<Attachment> attachments) {
    final trimmed = text.trim();
    if (trimmed.isNotEmpty) return trimmed;
    if (attachments.isEmpty) return trimmed;

    final imageCount =
        attachments.where((a) => a.type == AttachmentType.image).length;
    final fileCount =
        attachments.where((a) => a.type != AttachmentType.image).length;
    final parts = <String>[];
    if (imageCount > 0) {
      parts.add('$imageCount 张图片');
    }
    if (fileCount > 0) {
      parts.add('$fileCount 个文件');
    }
    return '附件消息（${parts.join('，')}）';
  }

  Future<List<Map<String, dynamic>>> _buildContentBlocks(
    String text,
    List<Attachment> attachments,
  ) async {
    final blocks = <Map<String, dynamic>>[];
    final trimmed = text.trim();
    if (trimmed.isNotEmpty) {
      blocks.add({'type': 'text', 'text': trimmed});
    }

    for (final attachment in attachments) {
      final file = File(attachment.path);
      if (!await file.exists()) {
        debugPrint('[ChatService] 附件不存在，已跳过: ${attachment.path}');
        continue;
      }

      final bytes = await file.readAsBytes();
      final data = base64Encode(bytes);
      if (attachment.type == AttachmentType.image) {
        blocks.add({
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': attachment.mime,
            'data': data,
          },
        });
        continue;
      }

      blocks.add({
        'type': 'file',
        'source_type': 'base64',
        'name': attachment.name,
        'media_type': attachment.mime,
        'data': data,
      });
    }

    return blocks;
  }

  void _mergeStreamElement(List<StreamElement> target, StreamElement incoming) {
    if (target.isEmpty) {
      target.add(incoming);
      return;
    }

    final last = target.last;

    // text chunk is emitted incrementally; merge into the previous open text block.
    if (incoming.type == StreamElementType.text &&
        last.type == StreamElementType.text &&
        !last.isComplete) {
      last.content += incoming.content;
      last.isComplete = incoming.isComplete;
      return;
    }

    // thinking incomplete chunks may be re-emitted as snapshots; replace the pending one.
    if (incoming.type == StreamElementType.thinking &&
        last.type == StreamElementType.thinking &&
        !last.isComplete) {
      last.content = incoming.content;
      last.isComplete = incoming.isComplete;
      last.metadata = incoming.metadata;
      return;
    }

    target.add(incoming);
  }

  Future<void> _ensureActiveChatReady() async {
    if (_activeChat == null) return;
    await _replaceActiveChat(await _repo.ensureChatExists(_activeChat!));
  }

  Future<bool> _recoverMissingChat() async {
    if (_activeChat == null) return false;
    final oldChat = _activeChat!;
    final recreated = await _repo.createChat(
      Chat(
        id: _uuid.v4(),
        title: oldChat.title.trim().isEmpty ? 'New Chat' : oldChat.title,
        createdAt: oldChat.createdAt,
        updatedAt: DateTime.now(),
        lastMessagePreview: oldChat.lastMessagePreview,
      ),
    );

    await _replaceActiveChat(recreated, oldChatId: oldChat.id);
    return true;
  }

  Future<void> _replaceActiveChat(Chat chat, {String? oldChatId}) async {
    final previousId = oldChatId ?? _activeChat?.id;
    final previousMessages =
        previousId == null ? _messages : await _repo.getMessages(previousId);

    final index = _chats.indexWhere((c) => c.id == chat.id);
    if (index == -1) {
      _chats.insert(0, chat);
    } else {
      _chats[index] = chat;
    }
    if (previousId != null && previousId != chat.id) {
      _chats.removeWhere((c) => c.id == previousId);
    }

    _activeChat = chat;

    if (previousId != null && previousId != chat.id) {
      if (previousMessages.isEmpty) {
        _messages = await _repo.getMessages(chat.id);
        notifyListeners();
        return;
      }
      final migrated = <Message>[];
      for (final msg in previousMessages) {
        final copied = Message(
          id: msg.id,
          chatId: chat.id,
          role: msg.role,
          content: msg.content,
          createdAt: msg.createdAt,
          attachments: List<Attachment>.from(msg.attachments),
          isStreaming: msg.isStreaming,
          streamElements: List<StreamElement>.from(msg.streamElements),
        );
        await _repo.addMessage(copied);
        migrated.add(copied);
      }
      _messages = migrated;
    } else {
      _messages = await _repo.getMessages(chat.id);
    }
    notifyListeners();
  }

  bool _isChatNotFoundError(CodingStreamEvent event) {
    if ((event.error ?? '').contains('chat_id not found')) {
      return true;
    }
    final raw = event.rawData;
    if (raw == null || raw.isEmpty) {
      return false;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final code = decoded['code'];
        if (code is int && code == _chatNotFoundErrorCode) {
          return true;
        }
        if (code is String && int.tryParse(code) == _chatNotFoundErrorCode) {
          return true;
        }
        final msg = decoded['msg']?.toString() ?? '';
        if (msg.contains('chat_id not found')) {
          return true;
        }
      }
    } catch (_) {
      return raw.contains('chat_id not found');
    }
    return false;
  }

  bool _isAuthInvalidError(
    String? message, {
    String? rawData,
    String? extra,
  }) {
    final text =
        '${message ?? ''} ${extra ?? ''} ${rawData ?? ''}'.toLowerCase();
    return text.contains('invalid token') ||
        text.contains('unauthorized') ||
        text.contains('token expired') ||
        text.contains('jwt expired') ||
        text.contains('401');
  }

  Future<void> _discardAssistantMessage(Message message) async {
    _streamProcessors.remove(message.id);
    _messages.removeWhere((m) => m.id == message.id);
    await _repo.deleteMessage(message.chatId, message.id);
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _streamProcessors.clear();
    _repo.dispose();
    _codingStreamClient.dispose();
    _transcribeClient.dispose();
    super.dispose();
  }
}

enum _GenerationResult {
  success,
  chatMissing,
  failed,
}
