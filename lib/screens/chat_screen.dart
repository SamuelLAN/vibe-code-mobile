import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/attachment.dart';
import '../models/message.dart';
import '../services/audio_recorder_service.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../widgets/attachment_tray.dart';
import '../widgets/input_bar.dart';
import '../widgets/message_bubble.dart';
import 'chat_list_drawer.dart';
import 'git_drawer/git_drawer.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Attachment> _pendingAttachments = [];
  final List<Attachment> _recentUploads = [];
  final AudioRecorderService _audioRecorder = AudioRecorderService();
  InputMode _inputMode = InputMode.voice;
  bool _isFullscreenInput = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final chat = context.read<ChatService>();
    final text = _textController.text.trim();
    if (text.isEmpty && _pendingAttachments.isEmpty) return;

    HapticFeedback.lightImpact();

    final attachments = List<Attachment>.from(_pendingAttachments);
    _pendingAttachments.clear();
    _textController.clear();
    setState(() {});

    await chat.sendUserMessage(text, attachments);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (photo == null) return;
    await _addAttachment(File(photo.path), AttachmentType.image, mime: 'image/jpeg');
  }

  Future<void> _pickFromGallery() async {
    final remainingSlots = 9 - _pendingAttachments.length;
    if (remainingSlots <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已达到最大附件数量限制 (9个)')),
      );
      return;
    }

    final picker = ImagePicker();
    final photos = await picker.pickMultiImage(imageQuality: 80);
    if (photos.isEmpty) return;

    final photosToAdd = photos.take(remainingSlots).toList();
    if (photosToAdd.length < photos.length) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已选择前 $remainingSlots 张图片，最多可添加 9 个附件')),
      );
    }

    for (final photo in photosToAdd) {
      await _addAttachment(File(photo.path), AttachmentType.image, mime: 'image/jpeg');
    }
  }

  Future<void> _pickFiles() async {
    final remainingSlots = 9 - _pendingAttachments.length;
    if (remainingSlots <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已达到最大附件数量限制 (9个)')),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;

    final filesToAdd = result.files.take(remainingSlots).toList();
    if (filesToAdd.length < result.files.length) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已选择前 $remainingSlots 个文件，最多可添加 9 个附件')),
      );
    }

    for (final file in filesToAdd) {
      if (file.path == null) continue;
      final extension = file.extension?.toLowerCase() ?? '';
      final mime = _getMimeType(extension);
      await _addAttachment(File(file.path!), AttachmentType.file, mime: mime);
    }
  }

  String _getMimeType(String extension) {
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      case 'txt':
        return 'text/plain';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _addAttachment(File file, AttachmentType type, {required String mime}) async {
    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(dir.path, 'attachments'));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final filename = p.basename(file.path);
    final target = File(p.join(targetDir.path, '${DateTime.now().millisecondsSinceEpoch}_$filename'));
    await file.copy(target.path);

    setState(() {
      final attachment = Attachment(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        path: target.path,
        name: filename,
        type: type,
        mime: mime,
        sizeBytes: file.lengthSync(),
        uploadProgress: 1.0,
      );
      _pendingAttachments.add(attachment);
      _recentUploads.insert(0, attachment);
      if (_recentUploads.length > 10) {
        _recentUploads.removeLast();
      }
    });
  }

  void _removeAttachment(String id) {
    setState(() {
      _pendingAttachments.removeWhere((a) => a.id == id);
    });
  }

  Future<void> _sendVoiceMessage() async {
    // 让用户选择音频文件（兼容旧方式）
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'flac', 'ogg', 'webm'],
    );
    
    if (result == null || result.files.isEmpty || result.files.first.path == null) {
      return;
    }

    final audioFile = File(result.files.first.path!);
    final fileSize = await audioFile.length();
    
    // 检查文件大小 (25MB = 25 * 1024 * 1024)
    if (fileSize > 25 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('音频文件不能超过 25MB')),
      );
      return;
    }

    final chat = context.read<ChatService>();
    HapticFeedback.lightImpact();

    await chat.sendVoiceMessage(audioFile);
    _scrollToBottom();
  }

  /// 处理录音完成回调（从 InputBar 的按住说话触发）
  Future<void> _onRecordingComplete(String filePath) async {
    final audioFile = File(filePath);
    final fileSize = await audioFile.length();
    
    // 检查文件大小
    if (fileSize > 25 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('录音时间过长，请缩短录音')),
      );
      return;
    }

    final chat = context.read<ChatService>();
    await chat.sendVoiceMessage(audioFile);
    _scrollToBottom();
  }

  void _toggleInputMode() {
    setState(() {
      _inputMode = _inputMode == InputMode.voice ? InputMode.text : InputMode.voice;
    });
  }

  Future<void> _showMediaPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a photo'),
              onTap: () async {
                Navigator.of(context).pop();
                await _pickFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () async {
                Navigator.of(context).pop();
                await _pickFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Recent uploads'),
              onTap: () async {
                Navigator.of(context).pop();
                await _showRecentUploads();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRecentUploads() async {
    if (_recentUploads.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No recent uploads yet.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _recentUploads.length,
          itemBuilder: (context, index) {
            final attachment = _recentUploads[index];
            return ListTile(
              leading: attachment.type == AttachmentType.image
                  ? Image.file(File(attachment.path), width: 40, height: 40, fit: BoxFit.cover)
                  : const Icon(Icons.insert_drive_file),
              title: Text(attachment.name),
              onTap: () {
                if (_pendingAttachments.length >= 9) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已达到最大附件数量限制 (9个)')),
                  );
                  return;
                }
                Navigator.of(context).pop();
                setState(() {
                  _pendingAttachments.add(attachment);
                });
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatService>();
    final auth = context.read<AuthService>();
    final messages = chat.messages;

    return Scaffold(
      drawer: const GitDrawer(),
      endDrawer: const ChatListDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(chat.activeChat?.title ?? 'Vibe Coding'),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_isFullscreenInput)
            Expanded(
              child: messages.isEmpty
                  ? Container(
                      color: Colors.white,
                      child: const Center(
                        child: Text(
                          '开始新对话',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return MessageBubble(
                        message: message,
                        onCopy: () {
                          Clipboard.setData(ClipboardData(text: message.content));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Message copied to clipboard.')),
                          );
                        },
                        onRetry: message.role == MessageRole.assistant
                            ? () => chat.retryLastUserMessage()
                            : null,
                      );
                    },
                    ),
            ),
          if (!_isFullscreenInput && _pendingAttachments.isNotEmpty)
            AttachmentTray(
              attachments: _pendingAttachments,
              onRemove: _removeAttachment,
            ),
          if (_isFullscreenInput)
            Expanded(
              child: InputBar.withRecorder(
                mode: _inputMode,
                controller: _textController,
                isGenerating: chat.isGenerating,
                onSend: _sendMessage,
                onStop: chat.stopGeneration,
                onToggleMode: _toggleInputMode,
                onPickMedia: _showMediaPicker,
                onPickFiles: _pickFiles,
                onVoiceSend: _sendVoiceMessage,
                recorder: _audioRecorder,
                onRecordingComplete: _onRecordingComplete,
                isFullscreen: true,
                onToggleFullscreen: () {
                  setState(() {
                    _isFullscreenInput = false;
                  });
                },
              ),
            )
          else
            InputBar.withRecorder(
              mode: _inputMode,
              controller: _textController,
              isGenerating: chat.isGenerating,
              onSend: _sendMessage,
              onStop: chat.stopGeneration,
              onToggleMode: _toggleInputMode,
              onPickMedia: _showMediaPicker,
              onPickFiles: _pickFiles,
              onVoiceSend: _sendVoiceMessage,
              recorder: _audioRecorder,
              onRecordingComplete: _onRecordingComplete,
              isFullscreen: false,
              onToggleFullscreen: () {
                setState(() {
                  _isFullscreenInput = true;
                });
              },
            ),
        ],
      ),
    );
  }
}
