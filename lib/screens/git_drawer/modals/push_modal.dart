import 'package:flutter/material.dart';

import '../../../../constants/colors.dart';
import '../widgets/widgets.dart';

class PushModal extends StatelessWidget {
  const PushModal({
    super.key,
    required this.branch,
    required this.remote,
    required this.aheadCount,
    required this.onConfirm,
  });

  final String branch;
  final String remote;
  final int aheadCount;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                    'Git Push',
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
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        InfoRow(label: '分支', child: BranchBadge(branch: branch)),
                        const SizedBox(height: 10),
                        InfoRow(
                          label: '远程',
                          child: Text(
                            remote,
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 10),
                        InfoRow(
                          label: '待推送',
                          child: Text(
                            '↑ $aheadCount',
                            style: const TextStyle(
                              color: GitColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    aheadCount > 0
                        ? '这将推送 $aheadCount 个提交到 $remote/$branch。是否继续？'
                        : '当前没有待推送提交。',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GitColors.push,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: aheadCount > 0 ? onConfirm : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.upload_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text('推送到 $remote/$branch'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
