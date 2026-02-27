import 'package:flutter/material.dart';

import '../../../../constants/colors.dart';
import '../../../../models/git_models.dart';

class ResetModal extends StatefulWidget {
  const ResetModal({
    super.key,
    required this.commits,
    required this.onConfirm,
  });

  final List<GitCommit> commits;
  final void Function(GitCommit commit, String type) onConfirm;

  @override
  State<ResetModal> createState() => _ResetModalState();
}

class _ResetModalState extends State<ResetModal> {
  int? _selectedIndex;
  String _resetType = 'mixed';

  @override
  void initState() {
    super.initState();
    if (widget.commits.isNotEmpty) {
      _selectedIndex = 0;
    }
  }

  @override
  void didUpdateWidget(covariant ResetModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.commits.isEmpty) {
      _selectedIndex = null;
      return;
    }
    final selected = _selectedIndex;
    if (selected == null || selected >= widget.commits.length) {
      _selectedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected =
        _selectedIndex == null ? null : widget.commits[_selectedIndex!];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '重置到提交',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: ['soft', 'mixed', 'hard'].map((t) {
                        final isSelected = _resetType == t;
                        return Expanded(
                          child: Padding(
                            padding:
                                EdgeInsets.only(right: t != 'hard' ? 8 : 0),
                            child: InkWell(
                              onTap: () => setState(() => _resetType = t),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? (t == 'hard'
                                          ? GitColors.error.withOpacity(0.15)
                                          : Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.15))
                                      : (isDark
                                          ? Colors.white10
                                          : Colors.grey[100]),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? (t == 'hard'
                                            ? GitColors.error
                                            : Theme.of(context)
                                                .colorScheme
                                                .primary)
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    t,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? (t == 'hard'
                                              ? GitColors.error
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .primary)
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _resetType == 'hard'
                            ? GitColors.error.withOpacity(0.08)
                            : (isDark ? Colors.white10 : Colors.grey[100]),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _resetType == 'hard'
                              ? GitColors.error.withOpacity(0.35)
                              : Colors.grey[300]!,
                        ),
                      ),
                      child: Text(
                        _modeDescription(_resetType),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: _resetType == 'hard'
                              ? GitColors.error
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '选择目标 Revision',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (widget.commits.isNotEmpty)
                          Text(
                            '${widget.commits.length} 个可选',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: widget.commits.isEmpty
                          ? Center(
                              child: Text('暂无可重置提交',
                                  style: TextStyle(color: Colors.grey[600])),
                            )
                          : ListView.separated(
                              itemCount: widget.commits.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final commit = widget.commits[index];
                                final isSelected = _selectedIndex == index;
                                return InkWell(
                                  key: ValueKey(
                                      'reset-candidate-${commit.hash}-$index'),
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () =>
                                      setState(() => _selectedIndex = index),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 120),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.1)
                                          : (isDark
                                              ? Colors.white10
                                              : Colors.grey[50]),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : (isDark
                                                ? Colors.white24
                                                : Colors.grey[300]!),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isSelected
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_unchecked,
                                          size: 20,
                                          color: isSelected
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                              : Colors.grey[500],
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                commit.shortHash,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontFamily: 'monospace',
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                commit.message.isEmpty
                                                    ? '(no message)'
                                                    : commit.message,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _formatDate(commit.date),
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[500]),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    if (selected != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '目标提交',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${selected.shortHash} · ${selected.message}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '命令预览: git reset --$_resetType ${selected.hash}',
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _resetType == 'hard'
                            ? GitColors.error
                            : Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: selected != null
                          ? () => _confirmAndSubmit(context, selected)
                          : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.restore_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(_resetType == 'hard'
                              ? '硬重置'
                              : '${_resetType[0].toUpperCase()}${_resetType.substring(1)} 重置'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndSubmit(BuildContext context, GitCommit commit) async {
    final isHard = _resetType == 'hard';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        return AlertDialog(
          title: Text(isHard ? '确认硬重置' : '确认重置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '将执行 git reset --$_resetType ${commit.hash}',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isHard
                    ? '这会移动 HEAD，并永久丢弃暂存区和工作区的改动。请再次确认。'
                    : _modeRiskHint(_resetType),
                style: TextStyle(
                  fontSize: 13,
                  color: isHard ? GitColors.error : Colors.grey[700],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: isHard
                    ? GitColors.error
                    : Theme.of(context).colorScheme.primary,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(isHard ? '确认硬重置' : '确认执行'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      widget.onConfirm(commit, _resetType);
    }
  }

  String _modeDescription(String mode) {
    switch (mode) {
      case 'soft':
        return 'soft: 仅移动 HEAD 到目标提交；暂存区和工作区保持不变，适合重新整理最近提交。';
      case 'hard':
        return 'hard: 移动 HEAD、重置暂存区并覆盖工作区。未提交改动会被丢弃。';
      case 'mixed':
      default:
        return 'mixed: 移动 HEAD 并重置暂存区，工作区改动保留（默认 reset 行为）。';
    }
  }

  String _modeRiskHint(String mode) {
    switch (mode) {
      case 'soft':
        return '只会回退提交历史，不会改动文件内容。';
      case 'mixed':
        return '会取消暂存状态，文件改动仍保留在工作区。';
      default:
        return '请确认此操作符合预期。';
    }
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}
