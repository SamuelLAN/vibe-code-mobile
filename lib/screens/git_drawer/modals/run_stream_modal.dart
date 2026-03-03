import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../constants/colors.dart';
import '../../../models/git_models.dart';

class RunStreamModal extends StatefulWidget {
  const RunStreamModal({
    super.key,
    required this.title,
    required this.stream,
  });

  final String title;
  final Stream<GitSseEvent> stream;

  @override
  State<RunStreamModal> createState() => _RunStreamModalState();
}

class _RunStreamModalState extends State<RunStreamModal> {
  static const double _autoFollowBottomThreshold = 28;
  final List<String> _lines = <String>[];
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<GitSseEvent>? _subscription;
  bool _completed = false;
  bool _errored = false;
  bool _shouldAutoFollow = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _appendLine('Connecting...');
    _subscription = widget.stream.listen(
      _onEvent,
      onError: (Object e) {
        _errored = true;
        _appendLine('[error] $e');
      },
      onDone: () {
        if (!_completed && !_errored) {
          _appendLine('Stream closed.');
        }
      },
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final distanceToBottom = position.maxScrollExtent - position.pixels;
    _shouldAutoFollow = distanceToBottom <= _autoFollowBottomThreshold;
  }

  void _onEvent(GitSseEvent event) {
    final eventName = event.name.toLowerCase();
    switch (eventName) {
      case 'started':
        _appendLine('[started] ${_formatEventPayload(event)}');
        break;
      case 'command':
        _appendLine('[command] ${_formatEventPayload(event)}');
        break;
      case 'log':
        final line = event.data?['line']?.toString();
        _appendLine(line ?? _fallbackRaw(event.rawData));
        break;
      case 'ping':
        // Heartbeat: do not pollute logs.
        break;
      case 'completed':
        _completed = true;
        _appendLine('[completed] ${_formatEventPayload(event)}');
        break;
      case 'error':
        _errored = true;
        _appendLine('[error] ${_formatEventPayload(event)}');
        break;
      default:
        _appendLine('[${event.name}] ${_formatEventPayload(event)}');
    }
  }

  String _formatEventPayload(GitSseEvent event) {
    if (event.data != null && event.data!.isNotEmpty) {
      final msg = event.data!['msg']?.toString();
      if (msg != null && msg.isNotEmpty) return msg;
      final line = event.data!['line']?.toString();
      if (line != null && line.isNotEmpty) return line;
      return jsonEncode(event.data);
    }
    return _fallbackRaw(event.rawData);
  }

  String _fallbackRaw(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? '-' : trimmed;
  }

  void _appendLine(String line) {
    if (!mounted) return;
    setState(() => _lines.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || !_shouldAutoFollow) return;
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(max);
    });
  }

  Future<void> _copyLogsToClipboard(String logs) async {
    if (logs.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: logs));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Build logs copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF171B22) : const Color(0xFFF8FAFC);
    final panelColor = isDark ? const Color(0xFF0F141B) : Colors.white;
    final titleColor = isDark ? const Color(0xFFEAF1FF) : const Color(0xFF182435);
    final logTextColor = isDark ? const Color(0xFFD5DFEC) : const Color(0xFF2A3A4F);
    final iconColor = isDark ? const Color(0xFFB8C4D4) : const Color(0xFF5A6B82);
    final joinedLines = _lines.join('\n');
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                  ),
                  _buildStateBadge(),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: joinedLines.trim().isEmpty
                        ? null
                        : () => _copyLogsToClipboard(joinedLines),
                    icon: Icon(Icons.copy_all_rounded, color: iconColor),
                    tooltip: 'Copy logs',
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: iconColor),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 2),
                decoration: BoxDecoration(
                  color: panelColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _lines.isEmpty
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Waiting for logs...',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF9BA8BA)
                                  : const Color(0xFF73839A),
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: SelectionArea(
                          child: SelectableText(
                            joinedLines,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              fontFamily: 'monospace',
                              color: logTextColor,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStateBadge() {
    if (_errored) {
      return _badge(
        label: 'error',
        color: GitColors.error,
      );
    }
    if (_completed) {
      return _badge(
        label: 'completed',
        color: GitColors.success,
      );
    }
    return _badge(
      label: 'running',
      color: GitColors.warning,
    );
  }

  Widget _badge({
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
