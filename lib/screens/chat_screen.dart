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
import '../services/audio_player_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/permission_service.dart';
import '../services/settings_service.dart';
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
  static const List<String> _defaultProjects = <String>[
    'plutux-board',
    'vibe-code-mobile',
  ];
  static const String _addProjectValue = '__add_project__';
  static const double _projectNameMinWidth = 96;
  static const double _projectNameMaxWidth = 220;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Attachment> _pendingAttachments = [];
  final List<Attachment> _recentUploads = [];
  final AudioRecorderService _audioRecorder = AudioRecorderService();
  final AudioPlayerService _audioPlayer = AudioPlayerService();
  final PermissionService _permissionService = PermissionService();
  late final List<String> _projects = List<String>.from(_defaultProjects);
  InputMode _inputMode = InputMode.voice;
  bool _isFullscreenInput = false;
  String _selectedProject = _defaultProjects.first;

  @override
  void initState() {
    super.initState();
    _audioPlayer.init();
    _scrollController.addListener(_handleHistoryPaginationScroll);
    _loadProjectSelection();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmupMicrophonePermission();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleHistoryPaginationScroll);
    _textController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _handleHistoryPaginationScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels <= 72) {
      final chat = context.read<ChatService>();
      if (chat.hasMoreHistory && !chat.isLoadingOlderHistory) {
        chat.loadOlderHistory();
      }
    }
  }

  Future<void> _warmupMicrophonePermission() async {
    try {
      await _permissionService.requestMicrophonePermission();
    } catch (e) {
      debugPrint('预请求麦克风权限失败: $e');
    }
  }

  Future<void> _loadProjectSelection() async {
    final settings = context.read<SettingsService>();
    final selected = await settings.getSelectedProjectName();
    if (selected == null || selected.trim().isEmpty) {
      await _selectProject(_selectedProject, refreshChats: false);
      return;
    }
    await _selectProject(selected.trim(), refreshChats: true);
  }

  String _repoPathForProject(String projectName) {
    switch (projectName) {
      case 'plutux-board':
        return '/Users/samuel/Documents/github/plutux-board';
      case 'vibe-code-mobile':
        return '/Users/samuel/Documents/github/vibe-code-mobile';
      default:
        return '/Users/samuel/Documents/github/$projectName';
    }
  }

  Future<void> _selectProject(
    String projectName, {
    bool refreshChats = true,
  }) async {
    if (!_projects.contains(projectName)) {
      _projects.add(projectName);
    }
    final settings = context.read<SettingsService>();
    await settings.setSelectedProjectName(projectName);
    await settings.setGitRepoPath(_repoPathForProject(projectName));
    if (refreshChats) {
      await context.read<ChatService>().switchProject();
    }
    if (!mounted) return;
    setState(() {
      _selectedProject = projectName;
    });
  }

  String? _projectNameFromGitHubUrl(String url) {
    final input = url.trim();
    if (input.isEmpty) return null;

    if (input.startsWith('git@github.com:')) {
      final repoPath = input.substring('git@github.com:'.length);
      final segments = repoPath.split('/');
      if (segments.length >= 2) {
        return segments[1].replaceAll('.git', '').trim();
      }
      return null;
    }

    final uri = Uri.tryParse(input);
    if (uri == null || !uri.host.toLowerCase().contains('github.com')) {
      return null;
    }
    if (uri.pathSegments.length < 2) return null;
    final repo = uri.pathSegments[1].replaceAll('.git', '').trim();
    return repo.isEmpty ? null : repo;
  }

  Future<void> _showAddProjectSheet() async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Project',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'GitHub URL',
                hintText: 'https://github.com/owner/repo',
                prefixIcon: Icon(Icons.link),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final projectName =
                          _projectNameFromGitHubUrl(controller.text);
                      if (projectName == null) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please enter a valid GitHub URL')),
                        );
                        return;
                      }

                      if (!_projects.contains(projectName)) {
                        _projects.add(projectName);
                      }
                      await _selectProject(projectName);

                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                    },
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    controller.dispose();
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

  void _dismissKeyboard() {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
      currentFocus.unfocus();
    }
  }

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final photo =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (photo == null) return;
    await _addAttachment(File(photo.path), AttachmentType.image,
        mime: 'image/jpeg');
  }

  Future<void> _pickFromGallery() async {
    final remainingSlots = 9 - _pendingAttachments.length;
    if (remainingSlots <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum attachment limit reached (9).')),
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
        SnackBar(
            content: Text(
                'Selected the first $remainingSlots images. You can add up to 9 attachments.')),
      );
    }

    for (final photo in photosToAdd) {
      await _addAttachment(File(photo.path), AttachmentType.image,
          mime: 'image/jpeg');
    }
  }

  Future<void> _pickFiles() async {
    final remainingSlots = 9 - _pendingAttachments.length;
    if (remainingSlots <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum attachment limit reached (9).')),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;

    final filesToAdd = result.files.take(remainingSlots).toList();
    if (filesToAdd.length < result.files.length) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Selected the first $remainingSlots files. You can add up to 9 attachments.')),
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

  Future<void> _addAttachment(File file, AttachmentType type,
      {required String mime}) async {
    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(dir.path, 'attachments'));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final filename = p.basename(file.path);
    final target = File(p.join(
        targetDir.path, '${DateTime.now().millisecondsSinceEpoch}_$filename'));
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

    if (result == null ||
        result.files.isEmpty ||
        result.files.first.path == null) {
      return;
    }

    final audioFile = File(result.files.first.path!);
    final fileSize = await audioFile.length();

    // 检查文件大小 (25MB = 25 * 1024 * 1024)
    if (fileSize > 25 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio files must be 25MB or smaller.')),
      );
      return;
    }

    final chat = context.read<ChatService>();
    HapticFeedback.lightImpact();

    final attachments = List<Attachment>.from(_pendingAttachments);
    _pendingAttachments.clear();
    setState(() {});

    await chat.sendVoiceMessage(audioFile, attachments: attachments);
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
        const SnackBar(
            content: Text('Recording is too long. Please shorten it.')),
      );
      return;
    }

    final chat = context.read<ChatService>();
    final attachments = List<Attachment>.from(_pendingAttachments);
    _pendingAttachments.clear();
    setState(() {});

    await chat.sendVoiceMessage(audioFile, attachments: attachments);
    _scrollToBottom();
  }

  void _toggleInputMode() {
    setState(() {
      _inputMode =
          _inputMode == InputMode.voice ? InputMode.text : InputMode.voice;
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
                  ? Image.file(File(attachment.path),
                      width: 40, height: 40, fit: BoxFit.cover)
                  : const Icon(Icons.insert_drive_file),
              title: Text(attachment.name),
              onTap: () {
                if (_pendingAttachments.length >= 9) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Maximum attachment limit reached (9).')),
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

  double _projectLabelWidth(
    BuildContext context,
    String projectName,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: projectName, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();

    return painter.width.clamp(_projectNameMinWidth, _projectNameMaxWidth);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatService>();
    final auth = context.read<AuthService>();
    final messages = chat.messages;
    const projectTextStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
    );
    final selectedProjectWidth =
        _projectLabelWidth(context, _selectedProject, projectTextStyle);

    return Scaffold(
      drawer: GitDrawer(
        key: ValueKey(_selectedProject),
        projectName: _selectedProject,
      ),
      endDrawer: const ChatListDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isDense: true,
                value: _selectedProject,
                alignment: Alignment.center,
                icon: const Icon(Icons.keyboard_arrow_down),
                items: [
                  ..._projects.map(
                    (project) => DropdownMenuItem<String>(
                      value: project,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: _projectNameMinWidth,
                          maxWidth: _projectNameMaxWidth,
                        ),
                        child: Text(
                          project,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: projectTextStyle,
                        ),
                      ),
                    ),
                  ),
                  const DropdownMenuItem<String>(
                    value: _addProjectValue,
                    child: Text('+ Add Project'),
                  ),
                ],
                selectedItemBuilder: (context) => [
                  ..._projects.map(
                    (project) => SizedBox(
                      width: selectedProjectWidth,
                      child: Text(
                        project,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: projectTextStyle,
                      ),
                    ),
                  ),
                  const SizedBox.shrink(),
                ],
                onChanged: (value) async {
                  if (value == null) return;
                  if (value == _addProjectValue) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _showAddProjectSheet();
                    });
                    return;
                  }
                  await _selectProject(value);
                },
              ),
            ),
            const SizedBox(height: 2),
            Text(
              chat.activeChat?.title ?? 'Vibe Coding',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
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
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard,
        child: Column(
          children: [
            if (chat.historyError != null &&
                chat.historyError!.trim().isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chat.historyError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => chat.clearHistoryError(),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            if (!_isFullscreenInput)
              Expanded(
                child: messages.isEmpty
                    ? Container(
                        color: Colors.white,
                        child: const Center(
                          child: Text(
                            'Start a new chat',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        key: ValueKey<String>(
                          'chat-list-${chat.activeChat?.id ?? 'none'}',
                        ),
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        itemCount: messages.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            if (chat.isLoadingOlderHistory) {
                              return const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }
                            if (chat.hasMoreHistory) {
                              return const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: Center(
                                  child: Text(
                                    'Scroll up to load more history',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          }
                          final message = messages[index - 1];
                          return MessageBubble(
                            key: ValueKey<String>(
                              '${chat.activeChat?.id ?? message.chatId}:${message.id}',
                            ),
                            message: message,
                            audioPlayer: _audioPlayer,
                            onCopy: () {
                              Clipboard.setData(
                                  ClipboardData(text: message.content));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Message copied to clipboard.')),
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
      ),
    );
  }
}
