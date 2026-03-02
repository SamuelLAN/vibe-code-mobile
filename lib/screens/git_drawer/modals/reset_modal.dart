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
                    'Reset to commit',
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
                          'Select target revision',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (widget.commits.isNotEmpty)
                          Text(
                            '${widget.commits.length} options',
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
                              child: Text('No commits available for reset',
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
                              'Target commit',
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
                              'Command preview: git reset --$_resetType ${selected.hash}',
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
                              ? 'Hard reset'
                              : '${_resetType[0].toUpperCase()}${_resetType.substring(1)} reset'),
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
          title: Text(isHard ? 'Confirm hard reset' : 'Confirm reset'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Will run git reset --$_resetType ${commit.hash}',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isHard
                    ? 'This will move HEAD and permanently discard staged and working tree changes. Please confirm again.'
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
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: isHard
                    ? GitColors.error
                    : Theme.of(context).colorScheme.primary,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(isHard ? 'Confirm hard reset' : 'Confirm'),
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
        return 'soft: move HEAD only. Index and working tree stay unchanged; useful for reorganizing recent commits.';
      case 'hard':
        return 'hard: move HEAD, reset index, and overwrite working tree. Uncommitted changes will be lost.';
      case 'mixed':
      default:
        return 'mixed: move HEAD and reset index while keeping working tree changes (default reset behavior).';
    }
  }

  String _modeRiskHint(String mode) {
    switch (mode) {
      case 'soft':
        return 'Only rewinds commit history; file contents remain unchanged.';
      case 'mixed':
        return 'Unstages changes while keeping file modifications in the working tree.';
      default:
        return 'Please confirm this operation is expected.';
    }
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} hr ago';
    return '${diff.inDays} day(s) ago';
  }
}
