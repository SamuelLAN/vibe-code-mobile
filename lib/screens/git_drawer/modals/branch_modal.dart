import 'package:flutter/material.dart';

import '../../../../mocks/git_data.dart';

class BranchModal extends StatelessWidget {
  final Function(String branch) onSelect;

  const BranchModal({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                    '切换分支',
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
            ...mockBranches.map((branch) {
              final isCurrentBranch = branch == currentBranch;
              return InkWell(
                onTap: () => onSelect(branch),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_tree_rounded,
                        size: 18,
                        color: isCurrentBranch
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[500],
                      ),
                      const SizedBox(width: 12),
                      Text(
                        branch,
                        style: TextStyle(
                          fontSize: 15,
                          color: isCurrentBranch
                              ? Theme.of(context).colorScheme.primary
                              : isDark
                                  ? Colors.white
                                  : Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      if (isCurrentBranch)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '当前',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
