import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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
  });

  final InputMode mode;
  final TextEditingController controller;
  final bool isGenerating;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onToggleMode;
  final VoidCallback onPickMedia;
  final VoidCallback onPickFiles;

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  String _transcript = '';

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      setState(() {
        _listening = false;
      });
      if (_transcript.trim().isNotEmpty) {
        widget.controller.text = _transcript.trim();
        widget.onToggleMode();
      }
      return;
    }

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) return;

    final available = await _speech.initialize();
    if (!available) return;

    setState(() {
      _listening = true;
      _transcript = '';
    });

    HapticFeedback.lightImpact();

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _transcript = result.recognizedWords;
        });
      },
    );
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant InputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode == InputMode.voice && widget.mode == InputMode.text && _listening) {
      _speech.stop();
      setState(() {
        _listening = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVoice = widget.mode == InputMode.voice;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: widget.onPickMedia,
                  icon: const Icon(Icons.photo_camera_outlined),
                ),
                IconButton(
                  onPressed: widget.onPickFiles,
                  icon: const Icon(Icons.attach_file),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.onToggleMode,
                  icon: Icon(isVoice ? Icons.keyboard : Icons.mic_none),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: isVoice
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              WaveformIndicator(active: _listening),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _listening
                                      ? (_transcript.isEmpty ? 'Listening...' : _transcript)
                                      : 'Tap the mic to start talking',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        )
                      : TextField(
                          controller: widget.controller,
                          maxLines: 4,
                          minLines: 1,
                          decoration: const InputDecoration(
                            hintText: 'Message the Vibe Coder',
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                if (isVoice)
                  IconButton.filled(
                    onPressed: _toggleListening,
                    icon: Icon(_listening ? Icons.stop_circle_outlined : Icons.mic),
                  )
                else
                  IconButton.filled(
                    onPressed: widget.isGenerating ? widget.onStop : widget.onSend,
                    icon: Icon(widget.isGenerating ? Icons.stop : Icons.send),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
