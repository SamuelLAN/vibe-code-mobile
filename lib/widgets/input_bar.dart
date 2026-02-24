import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/audio_recorder_service.dart';
import 'waveform_indicator.dart';

enum InputMode { voice, text }

class InputBar extends StatefulWidget {
  const InputBar({
    super.key,
    required this.mode,
    required this.controller,
    required this.isGenerating,
    required this.onSend,
    required this.onStop,
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
    required this.controller,
    required this.isGenerating,
    required this.onSend,
    required this.onStop,
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
  final TextEditingController controller;
  final bool isGenerating;
  final VoidCallback onSend;
  final VoidCallback onStop;
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
  bool _isRecording = false;
  bool _isCancelling = false;
  double _dragY = 0;
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
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: Color(0xFF2196F3),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: widget.onSend,
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.send, size: 20, color: Colors.white),
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
      icon: const Icon(Icons.keyboard_arrow_down, size: 30, color: Colors.black87),
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
                  border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2), width: 0.5)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: widget.onPickMedia,
                      icon: const Icon(Icons.camera_alt_outlined, size: 30, color: Colors.black87),
                    ),
                    Expanded(
                      child: isVoice
                          ? GestureDetector(
                              onPanStart: _onPanStart,
                              onPanUpdate: _onPanUpdate,
                              onPanEnd: _onPanEnd,
                              child: Container(
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.grey.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: const Text(
                                  '按住说话',
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
                                  hintText: '发消息...',
                                  hintStyle: TextStyle(color: Colors.grey),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  isDense: true,
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                    ),
                    if (_isFocused && _hasText) ...[
                      _buildSendButton(),
                    ] else if (_hasMultipleLines) ...[
                      _buildFullscreenButton(),
                      IconButton(
                        onPressed: widget.onToggleMode,
                        icon: Icon(isVoice ? Icons.keyboard_alt_outlined : Icons.mic_none_outlined, size: 30, color: Colors.black87),
                      ),
                      IconButton(
                        onPressed: widget.onPickFiles,
                        icon: const Icon(Icons.add_circle_outline, size: 30, color: Colors.black87),
                      ),
                    ] else ...[
                      IconButton(
                        onPressed: widget.onToggleMode,
                        icon: Icon(isVoice ? Icons.keyboard_alt_outlined : Icons.mic_none_outlined, size: 30, color: Colors.black87),
                      ),
                      IconButton(
                        onPressed: widget.onPickFiles,
                        icon: const Icon(Icons.add_circle_outline, size: 30, color: Colors.black87),
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
                border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2), width: 0.5)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onPickMedia,
                    icon: const Icon(Icons.camera_alt_outlined, size: 30, color: Colors.black87),
                  ),
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
                    hintText: '发消息...',
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

  void _onPanStart(DragStartDetails details) async {
    // 如果有录音服务，开始录音
    if (widget._recorder != null) {
      await widget._recorder!.startRecording();
    }
    setState(() {
      _isRecording = true;
      _isCancelling = false;
      _dragY = 0;
    });
    HapticFeedback.mediumImpact();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isRecording) return;
    setState(() {
      _dragY = -details.localPosition.dy;
      _isCancelling = _dragY > _cancelThreshold;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _endRecording();
  }

  void _endRecording() async {
    if (!_isRecording) return;

    if (!_isCancelling) {
      // 停止录音并获取文件路径
      String? filePath;
      if (widget._recorder != null) {
        filePath = await widget._recorder!.stopRecording();
      }

      if (filePath != null && widget.onRecordingComplete != null) {
        // 回调录音文件路径
        widget.onRecordingComplete!(filePath);
      } else if (widget.onVoiceSend != null) {
        // 兼容旧的回调
        widget.onVoiceSend!();
      } else {
        widget.onSend();
      }
    } else {
      // 取消录音
      if (widget._recorder != null) {
        await widget._recorder!.cancelRecording();
      }
    }

    setState(() {
      _isRecording = false;
      _isCancelling = false;
    });
    HapticFeedback.lightImpact();
  }

  Widget _buildRecordingOverlay() {
    final baseColor = _isCancelling ? Colors.red : const Color(0xFF2196F3);
    final text = _isCancelling ? '松手取消' : '松手发送，上移取消';

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
