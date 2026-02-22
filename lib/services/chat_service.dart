import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/attachment.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_repository.dart';

class ChatService extends ChangeNotifier {
  ChatService({ChatRepository? repository}) : _repo = repository ?? ChatRepository();

  final ChatRepository _repo;
  final Uuid _uuid = const Uuid();

  List<Chat> _chats = [];
  Chat? _activeChat;
  List<Message> _messages = [];
  bool _isGenerating = false;
  String? _error;
  Timer? _streamTimer;

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
      await _repo.createChat(chat);
      _chats = [chat];
    }
    await selectChat(_chats.first.id);
  }

  Future<void> refreshChats() async {
    _chats = await _repo.getChats();
    if (_activeChat != null) {
      final activeId = _activeChat!.id;
      _activeChat = _chats.firstWhere((chat) => chat.id == activeId, orElse: () => _chats.first);
    }
    notifyListeners();
  }

  Future<void> selectChat(String chatId) async {
    _activeChat = _chats.firstWhere((chat) => chat.id == chatId);
    _messages = await _repo.getMessages(chatId);
    notifyListeners();
  }

  Future<void> newChat() async {
    final chat = Chat(
      id: _uuid.v4(),
      title: 'New Chat',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _repo.createChat(chat);
    _chats.insert(0, chat);
    await selectChat(chat.id);
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

  Future<void> sendUserMessage(String text, List<Attachment> attachments) async {
    if (_activeChat == null) return;
    _error = null;

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

    await _updateChatMeta(text);
    notifyListeners();

    await _generateAssistantResponse(text);
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
    if (lastUser.content.isEmpty) return;
    await _generateAssistantResponse(lastUser.content);
  }

  void stopGeneration() {
    _streamTimer?.cancel();
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
    }
    notifyListeners();
  }

  Future<void> _updateChatMeta(String text) async {
    if (_activeChat == null) return;
    if (_activeChat!.title == 'New Chat') {
      _activeChat!.title = text.length > 32 ? '${text.substring(0, 32)}…' : text;
    }
    _activeChat!.updatedAt = DateTime.now();
    _activeChat!.lastMessagePreview = text.length > 60 ? '${text.substring(0, 60)}…' : text;
    await _repo.updateChat(_activeChat!);
    await refreshChats();
  }

  Future<void> _generateAssistantResponse(String prompt) async {
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

    const response =
        'Here\'s a focused plan for your request:\n\n'
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
        notifyListeners();
        return;
      }
      assistantMessage.content += response[index];
      index += 1;
      notifyListeners();
    });
  }
}
