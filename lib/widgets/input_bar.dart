import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  });

  final InputMode mode;
  final TextEditingController controller;
  final bool isGenerating;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onToggleMode;
  final VoidCallback onPickMedia;
  final VoidCallback onPickFiles;
  final VoidCallback? onVoiceSend;

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  bool _isRecording = false;
  bool _isCancelling = false;
  double _dragY = 0;
  static const double _cancelThreshold = 100.0;

  void _onLongPressStart(LongPressStartDetails details) {
    setState(() {
      _isRecording = true;
      _isCancelling = false;
      _dragY = 0;
    });
    HapticFeedback.mediumImpact();
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isRecording) return;
    setState(() {
      _dragY = -details.localOffsetFromOrigin.dy;
      _isCancelling = _dragY > _cancelThreshold;
    });
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (!_isRecording) return;
    
    if (!_isCancelling) {
      if (widget.onVoiceSend != null) {
        widget.onVoiceSend!();
      } else {
        widget.onSend();
      }
    }

    setState(() {
      _isRecording = false;
      _isCancelling = false;
    });
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
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
                              onLongPressStart: _onLongPressStart,
                              onLongPressMoveUpdate: _onLongPressMoveUpdate,
                              onLongPressEnd: _onLongPressEnd,
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
                                maxLines: 4,
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
                    IconButton(
                      onPressed: widget.onToggleMode,
                      icon: Icon(isVoice ? Icons.keyboard_alt_outlined : Icons.mic_none_outlined, size: 30, color: Colors.black87),
                    ),
                    IconButton(
                      onPressed: widget.onPickFiles,
                      icon: const Icon(Icons.add_circle_outline, size: 30, color: Colors.black87),
                    ),
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
