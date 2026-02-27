import 'package:flutter/material.dart';

import '../../../../models/git_models.dart';

class FileDiffModal extends StatefulWidget {
  const FileDiffModal({
    super.key,
    required this.diff,
  });

  final GitFileDiff diff;

  @override
  State<FileDiffModal> createState() => _FileDiffModalState();
}

class _FileDiffModalState extends State<FileDiffModal> {
  _DiffPane _pane = _DiffPane.after;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final before = widget.diff.beforeContent;
    final after = widget.diff.afterContent;
    final patch = widget.diff.patch;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'View changes',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.diff.path,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.grey[600]),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _paneButton(context, label: '改前', pane: _DiffPane.before),
                  const SizedBox(width: 8),
                  _paneButton(context, label: '改后', pane: _DiffPane.after),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF111111)
                        : const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black12),
                  ),
                  child: _buildCodeContent(
                    isDark: isDark,
                    before: before,
                    after: after,
                    patch: patch,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paneButton(
    BuildContext context, {
    required String label,
    required _DiffPane pane,
  }) {
    final isSelected = _pane == pane;
    final color = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _pane = pane),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? color : Colors.grey[350]!),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? color : Colors.grey[700],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeContent({
    required bool isDark,
    required String? before,
    required String? after,
    required String? patch,
  }) {
    final content = _pane == _DiffPane.before ? before : after;
    final fallback = patch;

    if (content == null || content.isEmpty) {
      if (fallback == null || fallback.isEmpty) {
        return Center(
          child: Text(
            _pane == _DiffPane.before ? '暂无改前内容' : '暂无改后内容',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        );
      }
      return _codeScroll(
        isDark: isDark,
        text: fallback,
        isFallback: true,
      );
    }

    return _codeScroll(
      isDark: isDark,
      text: content,
      isFallback: false,
    );
  }

  Widget _codeScroll({
    required bool isDark,
    required String text,
    required bool isFallback,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isFallback)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Text(
              '当前仅返回 diff patch，未提供完整改前/改后文件内容。',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                text,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  fontFamily: 'monospace',
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _DiffPane {
  before,
  after,
}
