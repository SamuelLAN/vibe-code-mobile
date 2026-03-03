import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/audio_recorder_service.dart';
import '../services/permission_service.dart';
import 'waveform_indicator.dart';

enum InputMode { voice, text }
enum ChatModelTier { flash, pro }

class InputBar extends StatefulWidget {
  const InputBar({
    super.key,
    required this.mode,
    required this.modelTier,
    required this.controller,
    required this.isGenerating,
    required this.onSend,
    required this.onStop,
    required this.onModelTierChanged,
    required this.onToggleMode,
    required this.onPickMedia,
    required this.onPickFiles,
    this.onVoiceSend,
    this.onRecordingComplete,
    this.isFullscreen = false,
    this.onToggleFullscreen,
  }) : _recorder = null;

  const InputBar.withRecorder({
    super.key,
    required this.mode,
    required this.modelTier,
    required this.controller,
    required this.isGenerating,
    required this.onSend,
    required this.onStop,
    required this.onModelTierChanged,
    required this.onToggleMode,
    required this.onPickMedia,
    required this.onPickFiles,
    this.onVoiceSend,
    required AudioRecorderService recorder,
    this.onRecordingComplete,
    this.isFullscreen = false,
    this.onToggleFullscreen,
  }) : _recorder = recorder;

  final InputMode mode;
  final ChatModelTier modelTier;
  final TextEditingController controller;
  final bool isGenerating;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final ValueChanged<ChatModelTier> onModelTierChanged;
  final VoidCallback onToggleMode;
  final VoidCallback onPickMedia;
  final VoidCallback onPickFiles;
  final VoidCallback? onVoiceSend;
  final void Function(String filePath)? onRecordingComplete;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;
  final AudioRecorderService? _recorder;

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  static const Duration _minVoiceDuration = Duration(seconds: 2);
  bool _isRecording = false;
  bool _isCancelling = false;
  bool _isStartingRecording = false;
  bool _isPointerHoldingVoice = false;
  bool _recorderStarted = false;
  double _dragY = 0;
  double? _voicePointerStartY;
  DateTime? _recordingStartedAt;
  int _recordingAttemptId = 0;
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();
  static const double _cancelThreshold = 100.0;

  bool get _isFullscreen => widget.isFullscreen;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    widget.controller.removeListener(_onTextChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  void _onTextChange() {
    setState(() {});
  }

  bool get _hasText => widget.controller.text.isNotEmpty;

  int get _lineCount {
    final text = widget.controller.text;
    if (text.isEmpty) return 0;
    return '\n'.allMatches(text).length + 1;
  }

  bool get _hasMultipleLines => _lineCount >= 2;

  Widget _buildSendButton() {
    final isStopping = widget.isGenerating;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isStopping ? Colors.red : const Color(0xFF2196F3),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: isStopping ? widget.onStop : widget.onSend,
        padding: EdgeInsets.zero,
        icon: Icon(
          isStopping ? Icons.stop : Icons.send,
          size: 20,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildFullscreenButton() {
    return IconButton(
      onPressed: widget.onToggleFullscreen,
      icon: const Icon(Icons.fullscreen, size: 28, color: Colors.black54),
    );
  }

  Widget _buildCollapseButton() {
    return IconButton(
      onPressed: widget.onToggleFullscreen,
      icon: const Icon(Icons.keyboard_arrow_down,
          size: 30, color: Colors.black87),
    );
  }

  Widget _buildModelTierSwitch() {
    Widget buildTierButton(ChatModelTier tier, String label) {
      final isSelected = widget.modelTier == tier;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onModelTierChanged(tier),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFE8EEF9) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.black87 : Colors.black54,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 94,
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          buildTierButton(ChatModelTier.flash, 'flash'),
          buildTierButton(ChatModelTier.pro, 'pro'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullscreen) {
      return _buildFullscreenInput();
    }

    final isVoice = widget.mode == InputMode.voice;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Builder(
          builder: (context) {
            return SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(26)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: widget.onPickMedia,
                      icon: const Icon(Icons.camera_alt_outlined,
                          size: 30, color: Colors.black87),
                    ),
                    Expanded(
                      child: isVoice
                          ? Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: _onVoicePointerDown,
                              onPointerMove: _onVoicePointerMove,
                              onPointerUp: _onVoicePointerUp,
                              onPointerCancel: _onVoicePointerCancel,
                              child: Container(
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.grey.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: const Text(
                                  'Hold to talk',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: TextField(
                                controller: widget.controller,
                                focusNode: _focusNode,
                                maxLines: 8,
                                minLines: 1,
                                style: const TextStyle(fontSize: 17),
                                decoration: const InputDecoration(
                                  hintText: 'Message...',
                                  hintStyle: TextStyle(color: Colors.grey),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  isDense: true,
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    _buildModelTierSwitch(),
                    if (widget.isGenerating || (_isFocused && _hasText)) ...[
                      _buildSendButton(),
                    ] else if (_hasMultipleLines) ...[
                      _buildFullscreenButton(),
                      IconButton(
                        onPressed: widget.onToggleMode,
                        icon: Icon(
                            isVoice
                                ? Icons.keyboard_alt_outlined
                                : Icons.mic_none_outlined,
                            size: 30,
                            color: Colors.black87),
                      ),
                      IconButton(
                        onPressed: widget.onPickFiles,
                        icon: const Icon(Icons.add_circle_outline,
                            size: 30, color: Colors.black87),
                      ),
                    ] else ...[
                      IconButton(
                        onPressed: widget.onToggleMode,
                        icon: Icon(
                            isVoice
                                ? Icons.keyboard_alt_outlined
                                : Icons.mic_none_outlined,
                            size: 30,
                            color: Colors.black87),
                      ),
                      IconButton(
                        onPressed: widget.onPickFiles,
                        icon: const Icon(Icons.add_circle_outline,
                            size: 30, color: Colors.black87),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        if (_isRecording)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildRecordingOverlay(),
          ),
      ],
    );
  }

  Widget _buildFullscreenInput() {
    return Container(
      height: MediaQuery.of(context).size.height,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: Colors.grey.withOpacity(0.2), width: 0.5)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onPickMedia,
                    icon: const Icon(Icons.camera_alt_outlined,
                        size: 30, color: Colors.black87),
                  ),
                  _buildModelTierSwitch(),
                  const Spacer(),
                  _buildCollapseButton(),
                ],
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 17),
                  decoration: const InputDecoration(
                    hintText: 'Message...',
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildSendButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onVoicePointerDown(PointerDownEvent event) {
    if (_isRecording || _isStartingRecording) return;

    _voicePointerStartY = event.position.dy;
    _isPointerHoldingVoice = true;
    _startVoiceRecording();
  }

  void _onVoicePointerMove(PointerMoveEvent event) {
    if (!_isRecording) return;

    final startY = _voicePointerStartY ?? event.position.dy;
    final dragY = startY - event.position.dy;
    setState(() {
      _dragY = dragY;
      _isCancelling = _dragY > _cancelThreshold;
    });
  }

  void _onVoicePointerUp(PointerUpEvent event) {
    _voicePointerStartY = null;
    _endRecording();
  }

  void _onVoicePointerCancel(PointerCancelEvent event) {
    _voicePointerStartY = null;
    if (_isRecording) {
      setState(() {
        _isCancelling = true;
      });
    }
    _endRecording();
  }

  void _startVoiceRecording() async {
    final attemptId = ++_recordingAttemptId;

    setState(() {
      _isRecording = true;
      _isStartingRecording = true;
      _recorderStarted = false;
      _recordingStartedAt = null;
      _isCancelling = false;
      _dragY = 0;
    });
    HapticFeedback.mediumImpact();

    // 如果有录音服务，先请求麦克风权限
    if (widget._recorder != null) {
      final permissionService = PermissionService();
      final hasPermission =
          await permissionService.requestMicrophonePermission();

      if (!mounted || attemptId != _recordingAttemptId) return;

      if (!hasPermission) {
        _isPointerHoldingVoice = false;
        // 权限被拒绝，提示用户
        if (mounted) {
          final shouldOpenSettings = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Microphone permission required'),
              content: const Text(
                  'Voice input requires microphone access. Open Settings?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );

          if (shouldOpenSettings == true) {
            await permissionService.openSettings();
          }
        }
        if (mounted && attemptId == _recordingAttemptId) {
          setState(() {
            _isRecording = false;
            _isStartingRecording = false;
            _recorderStarted = false;
            _recordingStartedAt = null;
            _isCancelling = false;
            _dragY = 0;
          });
        }
        return;
      }

      // 开始录音
      final filePath = await widget._recorder!.startRecording();

      if (!mounted || attemptId != _recordingAttemptId) return;

      // 如果录音失败（可能是模拟器或其他问题）
      if (filePath == null) {
        _isPointerHoldingVoice = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Unable to start recording. Please allow microphone access in system settings.'),
              duration: Duration(seconds: 3),
            ),
          );
          setState(() {
            _isRecording = false;
            _isStartingRecording = false;
            _recorderStarted = false;
            _recordingStartedAt = null;
            _isCancelling = false;
            _dragY = 0;
          });
        }
        return;
      }
    }

    if (!mounted || attemptId != _recordingAttemptId) return;

    setState(() {
      _isStartingRecording = false;
      _recorderStarted = true;
      _recordingStartedAt = DateTime.now();
    });

    // 用户在录音真正开始前已经松手，启动完成后立即结束/取消。
    if (!_isPointerHoldingVoice) {
      _endRecording();
    }
  }

  void _endRecording() async {
    if (!_isRecording) return;
    _isPointerHoldingVoice = false;

    if (_isStartingRecording) {
      return;
    }

    if (!_isCancelling) {
      final isTooShort = _recorderStarted &&
          _recordingStartedAt != null &&
          DateTime.now().difference(_recordingStartedAt!) < _minVoiceDuration;
      if (isTooShort) {
        if (widget._recorder != null) {
          await widget._recorder!.cancelRecording();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording too short, canceled.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        // 停止录音并获取文件路径
        String? filePath;
        if (widget._recorder != null && _recorderStarted) {
          try {
            filePath = await widget._recorder!.stopRecording();
          } catch (e) {
            debugPrint('Failed to stop recording: $e');
          }
        }

        if (filePath != null && widget.onRecordingComplete != null) {
          // 回调录音文件路径
          widget.onRecordingComplete!(filePath);
        } else if (filePath == null) {
          // 录音失败，提示用户去设置中开启权限
          debugPrint('Recording failed or file path is empty');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Please allow microphone access in system settings.'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else if (widget.onVoiceSend != null) {
          // 兼容旧的回调
          widget.onVoiceSend!();
        } else {
          widget.onSend();
        }
      }
    } else {
      // 取消录音
      if (widget._recorder != null) {
        await widget._recorder!.cancelRecording();
      }
    }

    setState(() {
      _isRecording = false;
      _isStartingRecording = false;
      _recorderStarted = false;
      _recordingStartedAt = null;
      _isCancelling = false;
      _dragY = 0;
    });
    HapticFeedback.lightImpact();
  }

  Widget _buildRecordingOverlay() {
    final baseColor = _isCancelling ? Colors.red : const Color(0xFF2196F3);
    final text = _isCancelling
        ? 'Release to cancel'
        : 'Release to send, slide up to cancel';

    return Container(
      width: MediaQuery.of(context).size.width,
      height: 300,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            baseColor.withOpacity(0.9),
            baseColor.withOpacity(0.6),
            baseColor.withOpacity(0.0),
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            text,
            key: ValueKey(_isCancelling),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  blurRadius: 4,
                  color: Colors.black26,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          WaveformIndicator(
            active: true,
            color: Colors.white,
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
