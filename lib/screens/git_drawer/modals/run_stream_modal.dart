import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

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
  final List<String> _lines = <String>[];
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<GitSseEvent>? _subscription;
  bool _completed = false;
  bool _errored = false;

  @override
  void initState() {
    super.initState();
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
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
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
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _buildStateBadge(),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _lines.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      itemCount: _lines.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SelectableText(
                          _lines[index],
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            fontFamily: 'monospace',
                            color: isDark ? Colors.white : Colors.black87,
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
        color: color.withOpacity(0.12),
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
