import 'dart:convert';

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
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lines = _buildDiffLines();

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
                  child: _buildSideBySideDiff(
                    isDark: isDark,
                    lines: lines,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideBySideDiff({
    required bool isDark,
    required List<_DiffLinePair> lines,
  }) {
    if (lines.isEmpty) {
      return Center(
        child: Text(
          'No diff to display',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      );
    }

    final dividerColor = isDark ? Colors.white12 : Colors.black12;
    return Column(
      children: [
        _buildLegend(isDark),
        Container(height: 1, color: dividerColor),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: lines.length,
            separatorBuilder: (_, __) => Container(
                height: 1, color: dividerColor.withValues(alpha: 0.7)),
            itemBuilder: (context, index) {
              final row = lines[index];
              return IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _buildCodeCell(
                        isDark: isDark,
                        lineNo: row.leftLineNo,
                        text: row.leftText,
                        sideType: row.leftType,
                      ),
                    ),
                    Container(width: 1, color: dividerColor),
                    Expanded(
                      child: _buildCodeCell(
                        isDark: isDark,
                        lineNo: row.rightLineNo,
                        text: row.rightText,
                        sideType: row.rightType,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLegend(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171717) : const Color(0xFFF3F4F6),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Before',
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
          _legendTag('Added', _LineType.added, isDark),
          const SizedBox(width: 6),
          _legendTag('Deleted', _LineType.deleted, isDark),
          const SizedBox(width: 6),
          _legendTag('Modified', _LineType.modified, isDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'After',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendTag(String label, _LineType type, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _lineBg(type, isDark),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: _lineAccent(type, isDark),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCodeCell({
    required bool isDark,
    required int? lineNo,
    required String? text,
    required _LineType sideType,
  }) {
    return Container(
      color: _lineBg(sideType, isDark),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              lineNo?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Colors.grey[500],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              text ?? '',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                fontFamily: 'monospace',
                color: text == null
                    ? Colors.transparent
                    : _lineAccent(sideType, isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_DiffLinePair> _buildDiffLines() {
    final before = widget.diff.beforeContent;
    final after = widget.diff.afterContent;
    if (before != null && after != null) {
      return _buildFromBeforeAfter(before, after);
    }
    final patch = widget.diff.patch;
    if (patch != null && patch.isNotEmpty) {
      return _buildFromPatch(patch);
    }
    return const [];
  }

  List<_DiffLinePair> _buildFromBeforeAfter(String before, String after) {
    final a = const LineSplitter().convert(before.replaceAll('\r\n', '\n'));
    final b = const LineSplitter().convert(after.replaceAll('\r\n', '\n'));
    if (a.isEmpty && b.isEmpty) return const [];

    final n = a.length;
    final m = b.length;
    if (n * m > 200000) {
      return _buildFromSimpleAlignment(a, b);
    }

    final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        if (a[i] == b[j]) {
          dp[i][j] = dp[i + 1][j + 1] + 1;
        } else {
          final down = dp[i + 1][j];
          final right = dp[i][j + 1];
          dp[i][j] = down >= right ? down : right;
        }
      }
    }

    final raw = <_DiffLinePair>[];
    var i = 0;
    var j = 0;
    var leftNo = 1;
    var rightNo = 1;

    while (i < n && j < m) {
      if (a[i] == b[j]) {
        raw.add(_DiffLinePair(
          leftLineNo: leftNo++,
          rightLineNo: rightNo++,
          leftText: a[i],
          rightText: b[j],
          leftType: _LineType.unchanged,
          rightType: _LineType.unchanged,
        ));
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        raw.add(_DiffLinePair(
          leftLineNo: leftNo++,
          rightLineNo: null,
          leftText: a[i],
          rightText: null,
          leftType: _LineType.deleted,
          rightType: _LineType.deleted,
        ));
        i++;
      } else {
        raw.add(_DiffLinePair(
          leftLineNo: null,
          rightLineNo: rightNo++,
          leftText: null,
          rightText: b[j],
          leftType: _LineType.added,
          rightType: _LineType.added,
        ));
        j++;
      }
    }

    while (i < n) {
      raw.add(_DiffLinePair(
        leftLineNo: leftNo++,
        rightLineNo: null,
        leftText: a[i++],
        rightText: null,
        leftType: _LineType.deleted,
        rightType: _LineType.deleted,
      ));
    }
    while (j < m) {
      raw.add(_DiffLinePair(
        leftLineNo: null,
        rightLineNo: rightNo++,
        leftText: null,
        rightText: b[j++],
        leftType: _LineType.added,
        rightType: _LineType.added,
      ));
    }

    return _collapseModify(raw);
  }

  List<_DiffLinePair> _buildFromSimpleAlignment(
    List<String> beforeLines,
    List<String> afterLines,
  ) {
    final maxLen = beforeLines.length > afterLines.length
        ? beforeLines.length
        : afterLines.length;
    final rows = <_DiffLinePair>[];
    for (var i = 0; i < maxLen; i++) {
      final left = i < beforeLines.length ? beforeLines[i] : null;
      final right = i < afterLines.length ? afterLines[i] : null;
      if (left == right && left != null) {
        rows.add(_DiffLinePair(
          leftLineNo: i + 1,
          rightLineNo: i + 1,
          leftText: left,
          rightText: right,
          leftType: _LineType.unchanged,
          rightType: _LineType.unchanged,
        ));
      } else if (left != null && right != null) {
        rows.add(_DiffLinePair(
          leftLineNo: i + 1,
          rightLineNo: i + 1,
          leftText: left,
          rightText: right,
          leftType: _LineType.modified,
          rightType: _LineType.modified,
        ));
      } else if (left != null) {
        rows.add(_DiffLinePair(
          leftLineNo: i + 1,
          rightLineNo: null,
          leftText: left,
          rightText: null,
          leftType: _LineType.deleted,
          rightType: _LineType.deleted,
        ));
      } else {
        rows.add(_DiffLinePair(
          leftLineNo: null,
          rightLineNo: i + 1,
          leftText: null,
          rightText: right,
          leftType: _LineType.added,
          rightType: _LineType.added,
        ));
      }
    }
    return rows;
  }

  List<_DiffLinePair> _buildFromPatch(String patch) {
    final lines = const LineSplitter().convert(patch.replaceAll('\r\n', '\n'));
    final rows = <_DiffLinePair>[];
    var leftNo = 1;
    var rightNo = 1;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('@@')) {
        final match =
            RegExp(r'@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@').firstMatch(line);
        if (match != null) {
          leftNo = int.tryParse(match.group(1) ?? '') ?? leftNo;
          rightNo = int.tryParse(match.group(2) ?? '') ?? rightNo;
        }
        continue;
      }
      if (line.startsWith('---') || line.startsWith('+++')) continue;

      if (line.startsWith('-') &&
          i + 1 < lines.length &&
          lines[i + 1].startsWith('+')) {
        rows.add(_DiffLinePair(
          leftLineNo: leftNo++,
          rightLineNo: rightNo++,
          leftText: line.substring(1),
          rightText: lines[i + 1].substring(1),
          leftType: _LineType.modified,
          rightType: _LineType.modified,
        ));
        i++;
        continue;
      }
      if (line.startsWith('-')) {
        rows.add(_DiffLinePair(
          leftLineNo: leftNo++,
          rightLineNo: null,
          leftText: line.substring(1),
          rightText: null,
          leftType: _LineType.deleted,
          rightType: _LineType.deleted,
        ));
      } else if (line.startsWith('+')) {
        rows.add(_DiffLinePair(
          leftLineNo: null,
          rightLineNo: rightNo++,
          leftText: null,
          rightText: line.substring(1),
          leftType: _LineType.added,
          rightType: _LineType.added,
        ));
      } else if (line.startsWith(' ')) {
        rows.add(_DiffLinePair(
          leftLineNo: leftNo++,
          rightLineNo: rightNo++,
          leftText: line.substring(1),
          rightText: line.substring(1),
          leftType: _LineType.unchanged,
          rightType: _LineType.unchanged,
        ));
      }
    }
    return rows;
  }

  List<_DiffLinePair> _collapseModify(List<_DiffLinePair> rows) {
    final output = <_DiffLinePair>[];
    var i = 0;
    while (i < rows.length) {
      final current = rows[i];
      final hasNext = i + 1 < rows.length;
      if (hasNext &&
          current.leftType == _LineType.deleted &&
          rows[i + 1].rightType == _LineType.added &&
          current.leftText != null &&
          rows[i + 1].rightText != null) {
        final next = rows[i + 1];
        output.add(_DiffLinePair(
          leftLineNo: current.leftLineNo,
          rightLineNo: next.rightLineNo,
          leftText: current.leftText,
          rightText: next.rightText,
          leftType: _LineType.modified,
          rightType: _LineType.modified,
        ));
        i += 2;
        continue;
      }
      output.add(current);
      i++;
    }
    return output;
  }

  Color _lineBg(_LineType type, bool isDark) {
    switch (type) {
      case _LineType.added:
        return isDark
            ? const Color.fromRGBO(46, 160, 67, 0.24)
            : const Color.fromRGBO(46, 160, 67, 0.14);
      case _LineType.deleted:
        return isDark
            ? const Color.fromRGBO(248, 81, 73, 0.24)
            : const Color.fromRGBO(248, 81, 73, 0.14);
      case _LineType.modified:
        return isDark
            ? const Color.fromRGBO(251, 188, 5, 0.22)
            : const Color.fromRGBO(251, 188, 5, 0.16);
      case _LineType.unchanged:
        return Colors.transparent;
    }
  }

  Color _lineAccent(_LineType type, bool isDark) {
    switch (type) {
      case _LineType.added:
        return isDark ? const Color(0xFF7EE787) : const Color(0xFF1A7F37);
      case _LineType.deleted:
        return isDark ? const Color(0xFFFFA198) : const Color(0xFFCF222E);
      case _LineType.modified:
        return isDark ? const Color(0xFFF2CC60) : const Color(0xFF9A6700);
      case _LineType.unchanged:
        return isDark ? Colors.white : Colors.black87;
    }
  }
}

class _DiffLinePair {
  const _DiffLinePair({
    required this.leftLineNo,
    required this.rightLineNo,
    required this.leftText,
    required this.rightText,
    required this.leftType,
    required this.rightType,
  });

  final int? leftLineNo;
  final int? rightLineNo;
  final String? leftText;
  final String? rightText;
  final _LineType leftType;
  final _LineType rightType;
}

enum _LineType {
  unchanged,
  added,
  deleted,
  modified,
}
