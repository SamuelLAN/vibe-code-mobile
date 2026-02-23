import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/colors.dart';
import '../mocks/git_data.dart';

enum GitOpStatus { idle, loading, success, error }

class GitDrawer extends StatefulWidget {
  const GitDrawer({super.key});

  @override
  State<GitDrawer> createState() => _GitDrawerState();
}

class _GitDrawerState extends State<GitDrawer> {
  GitOpStatus _pullStatus = GitOpStatus.idle;
  GitOpStatus _pushStatus = GitOpStatus.idle;
  GitOpStatus _commitStatus = GitOpStatus.idle;
  GitOpStatus _resetStatus = GitOpStatus.idle;
  GitOpStatus _stashStatus = GitOpStatus.idle;

  String? _toastMessage;
  Color? _toastColor;
  bool _showingToast = false;

  void _showToast(String message, {Color? color}) {
    setState(() {
      _toastMessage = message;
      _toastColor = color ?? GitColors.success;
      _showingToast = true;
    });
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _showingToast = false;
        });
      }
    });
  }

  Future<void> _runOp(
    GitOpStatus status,
    String successMsg, {
    int delay = 1800,
    String? failMsg,
    required Function(GitOpStatus) setStatus,
  }) async {
    HapticFeedback.mediumImpact();
    setStatus(GitOpStatus.loading);
    await Future.delayed(Duration(milliseconds: delay));
    // Mock success for demo
    setStatus(GitOpStatus.success);
    _showToast(successMsg);
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setStatus(GitOpStatus.idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Drawer(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(theme, isDark),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      const SizedBox(height: 8),
                      _buildSectionTitle('同步'),
                      _buildGitOpButton(
                        icon: Icons.download_rounded,
                        label: 'Pull',
                        sublabel: '从 origin 拉取并合并',
                        status: _pullStatus,
                        accentColor: GitColors.pull,
                        onPress: () => _runOp(
                          _pullStatus,
                          '已是最新版本',
                          delay: 2000,
                          setStatus: (s) => setState(() => _pullStatus = s),
                        ),
                      ),
                      _buildGitOpButton(
                        icon: Icons.upload_rounded,
                        label: 'Push',
                        sublabel: '$commitsAhead 个提交待推送',
                        status: _pushStatus,
                        accentColor: GitColors.push,
                        onPress: () => _showPushModal(context),
                      ),
                      const SizedBox(height: 16),
                      _buildSectionTitle('更改'),
                      _buildGitOpButton(
                        icon: Icons.commit_rounded,
                        label: 'Commit',
                        sublabel: '${mockFileChanges.length} 个文件已更改',
                        status: _commitStatus,
                        accentColor: GitColors.commit,
                        onPress: () => _showCommitModal(context),
                      ),
                      _buildGitOpButton(
                        icon: Icons.restore_rounded,
                        label: 'Reset',
                        sublabel: '重置到之前的提交',
                        status: _resetStatus,
                        accentColor: GitColors.reset,
                        onPress: () => _showResetModal(context),
                      ),
                      const SizedBox(height: 16),
                      _buildSectionTitle('高级'),
                      _buildGitOpButton(
                        icon: Icons.archive_rounded,
                        label: 'Stash 更改',
                        sublabel: '保存更改以供稍后使用',
                        status: _stashStatus,
                        accentColor: GitColors.stash,
                        onPress: () => _runOp(
                          _stashStatus,
                          '更改已暂存',
                          delay: 1200,
                          setStatus: (s) => setState(() => _stashStatus = s),
                        ),
                      ),
                      _buildGitOpButton(
                        icon: Icons.history_rounded,
                        label: 'Git Log',
                        sublabel: '查看最近的提交',
                        status: GitOpStatus.idle,
                        accentColor: GitColors.log,
                        onPress: () => _showLogModal(context),
                      ),
                      _buildGitOpButton(
                        icon: Icons.account_tree_rounded,
                        label: '切换分支',
                        sublabel: '当前在 $currentBranch',
                        status: GitOpStatus.idle,
                        accentColor: GitColors.branch,
                        onPress: () => _showBranchModal(context),
                      ),
                      const SizedBox(height: 16),
                      _buildStatusCard(theme, isDark),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
            if (_showingToast)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: _buildToast(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.account_tree_rounded,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  currentBranch,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '↑$commitsAhead',
              style: TextStyle(
                color: GitColors.success,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[500],
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildGitOpButton({
    required IconData icon,
    required String label,
    required String sublabel,
    required GitOpStatus status,
    required Color accentColor,
    required VoidCallback onPress,
  }) {
    final isLoading = status == GitOpStatus.loading;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isLoading ? null : onPress,
          child: Opacity(
            opacity: isLoading ? 0.6 : 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: accentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          sublabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusIcon(status),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(GitOpStatus status) {
    switch (status) {
      case GitOpStatus.idle:
        return Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]);
      case GitOpStatus.loading:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: GitColors.warning,
          ),
        );
      case GitOpStatus.success:
        return Icon(Icons.check, size: 16, color: GitColors.success);
      case GitOpStatus.error:
        return Icon(Icons.warning_rounded, size: 16, color: GitColors.error);
    }
  }

  Widget _buildStatusCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '工作树状态',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          ...mockFileChanges.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: f.staged ? GitColors.success : GitColors.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f.path,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      f.status == 'deleted'
                          ? 'D'
                          : f.status == 'added'
                              ? 'A'
                              : 'M',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: f.status == 'deleted'
                            ? GitColors.deleted
                            : f.status == 'added'
                                ? GitColors.added
                                : GitColors.modified,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildToast() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _toastColor ?? GitColors.success,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              _toastColor == GitColors.error ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _toastMessage ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCommitModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommitModal(
        onConfirm: (msg, files) {
          Navigator.pop(context);
          _runOp(
            _commitStatus,
            '提交: "${msg.length > 30 ? '${msg.substring(0, 30)}...' : msg}"',
            delay: 1600,
            setStatus: (s) => setState(() => _commitStatus = s),
          );
        },
      ),
    );
  }

  void _showResetModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ResetModal(
        onConfirm: (commit, type) {
          Navigator.pop(context);
          _runOp(
            _resetStatus,
            '重置到 ${commit.shortHash} ($type)',
            delay: 1500,
            setStatus: (s) => setState(() => _resetStatus = s),
          );
        },
      ),
    );
  }

  void _showPushModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PushModal(
        onConfirm: () {
          Navigator.pop(context);
          _runOp(
            _pushStatus,
            '已推送 $commitsAhead 个提交到 origin/$currentBranch',
            delay: 2200,
            failMsg: '推送被拒绝 - 请先拉取',
            setStatus: (s) => setState(() => _pushStatus = s),
          );
        },
      ),
    );
  }

  void _showLogModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 300),
      ),
      builder: (context) => const LogModal(),
    );
  }

  void _showBranchModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BranchModal(
        onSelect: (branch) {
          Navigator.pop(context);
          _showToast('已切换到分支 \'$branch\'');
        },
      ),
    );
  }
}

class CommitModal extends StatefulWidget {
  final Function(String message, List<GitFileChange> files) onConfirm;

  const CommitModal({super.key, required this.onConfirm});

  @override
  State<CommitModal> createState() => _CommitModalState();
}

class _CommitModalState extends State<CommitModal> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late List<GitFileChange> _files;

  @override
  void initState() {
    super.initState();
    _files = mockFileChanges.map((f) => GitFileChange(path: f.path, status: f.status, staged: f.staged)).toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleStage(String path) {
    setState(() {
      _files = _files.map((f) => f.path == path ? GitFileChange(path: f.path, status: f.status, staged: !f.staged) : f).toList();
    });
  }

  void _stageAll() {
    setState(() {
      _files = _files.map((f) => GitFileChange(path: f.path, status: f.status, staged: true)).toList();
    });
  }

  void _unstageAll() {
    setState(() {
      _files = _files.map((f) => GitFileChange(path: f.path, status: f.status, staged: false)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
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
                      'Git Commit',
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
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLength: 72,
                        maxLines: 3,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          hintText: '提交信息...',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          filled: true,
                          fillColor: isDark ? Colors.white10 : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          counterText: '',
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(label: '全部暂存', onTap: _stageAll),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionButton(label: '取消暂存', onTap: _unstageAll),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._files.map((f) => InkWell(
                          onTap: () => _toggleStage(f.path),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: f.staged ? Theme.of(context).colorScheme.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: f.staged ? Theme.of(context).colorScheme.primary : Colors.grey[400]!,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: f.staged
                                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    f.path,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontFamily: 'monospace',
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  f.status,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: f.status == 'deleted'
                                        ? GitColors.deleted
                                        : f.status == 'added'
                                            ? GitColors.added
                                            : GitColors.modified,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _controller.text.trim().isNotEmpty
                          ? () => widget.onConfirm(_controller.text.trim(), _files.where((f) => f.staged).toList())
                          : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.commit_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text('提交 ${_files.where((f) => f.staged).length} 个文件'),
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
    ),
    );
  }
}

class ResetModal extends StatefulWidget {
  final Function(GitCommit commit, String type) onConfirm;

  const ResetModal({super.key, required this.onConfirm});

  @override
  State<ResetModal> createState() => _ResetModalState();
}

class _ResetModalState extends State<ResetModal> {
  GitCommit? _selected;
  String _resetType = 'mixed';

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
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: ['soft', 'mixed', 'hard'].map((t) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: t != 'hard' ? 8 : 0),
                              child: InkWell(
                                onTap: () => setState(() => _resetType = t),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _resetType == t
                                        ? t == 'hard'
                                            ? GitColors.error.withOpacity(0.15)
                                            : Theme.of(context).colorScheme.primary.withOpacity(0.15)
                                        : isDark
                                            ? Colors.white10
                                            : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _resetType == t
                                          ? t == 'hard'
                                              ? GitColors.error
                                              : Theme.of(context).colorScheme.primary
                                          : Colors.grey[300]!,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      t,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _resetType == t
                                            ? t == 'hard'
                                                ? GitColors.error
                                                : Theme.of(context).colorScheme.primary
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )).toList(),
                    ),
                    if (_resetType == 'hard') ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: GitColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: GitColors.error.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_rounded, size: 16, color: GitColors.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '硬重置将丢弃所有未提交的更改！',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: GitColors.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ...mockCommits.map((c) => InkWell(
                          onTap: () => setState(() => _selected = c),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: _selected?.hash == c.hash
                                  ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                                  : null,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _selected?.hash == c.hash
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.shortHash,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        c.message,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        c.date,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_selected?.hash == c.hash)
                                  Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary),
                              ],
                            ),
                          ),
                        )),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _resetType == 'hard' ? GitColors.error : Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _selected != null
                          ? () => widget.onConfirm(_selected!, _resetType)
                          : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.restore_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(_resetType == 'hard'
                              ? '⚠ 硬重置'
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
}

class PushModal extends StatelessWidget {
  final VoidCallback onConfirm;

  const PushModal({super.key, required this.onConfirm});

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
                        _InfoRow(label: '分支', child: _BranchBadge(branch: currentBranch)),
                        const SizedBox(height: 10),
                        _InfoRow(label: '远程', child: Text('origin', style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                        const SizedBox(height: 10),
                        _InfoRow(
                          label: '待推送',
                          child: Text('↑ $commitsAhead', style: TextStyle(color: GitColors.success, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '这将推送 $commitsAhead 个提交到 origin/$currentBranch。是否继续？',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GitColors.push,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onConfirm,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.upload_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text('推送到 origin/$currentBranch'),
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

class LogModal extends StatefulWidget {
  const LogModal({super.key});

  @override
  State<LogModal> createState() => _LogModalState();
}

class _LogModalState extends State<LogModal> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FractionalTranslation(
          translation: _slideAnimation.value,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: child,
          ),
        );
      },
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '提交日志',
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
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: mockCommits.length,
                  itemBuilder: (context, index) {
                    final commit = mockCommits[index];
                    final isLast = index == mockCommits.length - 1;
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: index == 0
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey[400],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              if (!isLast)
                                Expanded(
                                  child: Container(
                                    width: 2,
                                    color: Colors.grey[300],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    commit.shortHash,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    commit.message,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${commit.author} · ${commit.date}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
            ...mockBranches.map((branch) => InkWell(
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
                          color: branch == currentBranch
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey[500],
                        ),
                        const SizedBox(width: 12),
                        Text(
                          branch,
                          style: TextStyle(
                            fontSize: 15,
                            color: branch == currentBranch
                                ? Theme.of(context).colorScheme.primary
                                : isDark
                                    ? Colors.white
                                    : Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        if (branch == currentBranch)
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
                )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _InfoRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
        child,
      ],
    );
  }
}

class _BranchBadge extends StatelessWidget {
  final String branch;

  const _BranchBadge({required this.branch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_tree_rounded,
            size: 12,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            branch,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
