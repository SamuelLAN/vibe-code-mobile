import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../constants/colors.dart';
import '../../../mocks/git_data.dart';
import 'enums.dart';
import 'modals/modals.dart';

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
  GitOpStatus _stashPopStatus = GitOpStatus.idle;

  ProjectOpStatus _npmStartStatus = ProjectOpStatus.stopped;
  ProjectOpStatus _npmInstallStatus = ProjectOpStatus.idle;

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
    setStatus(GitOpStatus.success);
    _showToast(successMsg);
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setStatus(GitOpStatus.idle);
    });
  }

  Future<void> _runProjectOp(
    ProjectOpStatus successStatus,
    String successMsg, {
    int delay = 1500,
    required Function(ProjectOpStatus) setStatus,
  }) async {
    HapticFeedback.mediumImpact();
    setStatus(ProjectOpStatus.running);
    await Future.delayed(Duration(milliseconds: delay));
    setStatus(successStatus);
    _showToast(successMsg);
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && successStatus != ProjectOpStatus.running) {
        setStatus(ProjectOpStatus.idle);
      }
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
                      _buildSectionTitle('项目运行'),
                      _buildProjectOpButton(
                        icon: Icons.play_arrow_rounded,
                        label: 'npm start',
                        sublabel: '启动开发服务器',
                        status: _npmStartStatus,
                        accentColor: GitColors.success,
                        isRunning: _npmStartStatus == ProjectOpStatus.running,
                        onPress: () => _runProjectOp(
                          ProjectOpStatus.running,
                          '开发服务器已启动',
                          setStatus: (s) => setState(() => _npmStartStatus = s),
                        ),
                        onStop: () => setState(() => _npmStartStatus = ProjectOpStatus.stopped),
                      ),
                      _buildProjectOpButton(
                        icon: Icons.download_rounded,
                        label: 'npm install',
                        sublabel: '安装项目依赖',
                        status: _npmInstallStatus,
                        accentColor: GitColors.commit,
                        onPress: () => _runProjectOp(
                          ProjectOpStatus.idle,
                          '依赖安装完成',
                          setStatus: (s) => setState(() => _npmInstallStatus = s),
                        ),
                      ),
                      _buildProjectOpButton(
                        icon: Icons.stop_rounded,
                        label: 'Stop',
                        sublabel: '停止所有运行中的服务',
                        status: ProjectOpStatus.stopped,
                        accentColor: GitColors.error,
                        onPress: () => _showToast('已停止所有服务', color: GitColors.warning),
                      ),
                      const SizedBox(height: 16),
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
                        icon: Icons.unarchive_rounded,
                        label: 'Stash Pop',
                        sublabel: '恢复暂存的更改',
                        status: _stashPopStatus,
                        accentColor: GitColors.stash,
                        onPress: () => _runOp(
                          _stashPopStatus,
                          '更改已恢复',
                          delay: 1200,
                          setStatus: (s) => setState(() => _stashPopStatus = s),
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
              style: const TextStyle(
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
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: GitColors.warning,
          ),
        );
      case GitOpStatus.success:
        return const Icon(Icons.check, size: 16, color: GitColors.success);
      case GitOpStatus.error:
        return const Icon(Icons.warning_rounded, size: 16, color: GitColors.error);
    }
  }

  Widget _buildProjectOpButton({
    required IconData icon,
    required String label,
    required String sublabel,
    required ProjectOpStatus status,
    required Color accentColor,
    required VoidCallback onPress,
    VoidCallback? onStop,
    bool isRunning = false,
  }) {
    final isLoading = status == ProjectOpStatus.idle && !isRunning;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isLoading ? null : (isRunning ? onStop : onPress),
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
                  _buildProjectStatusIcon(status, isRunning: isRunning),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProjectStatusIcon(ProjectOpStatus status, {bool isRunning = false}) {
    if (isRunning) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: GitColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            '运行中',
            style: TextStyle(
              fontSize: 12,
              color: GitColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    switch (status) {
      case ProjectOpStatus.idle:
        return Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]);
      case ProjectOpStatus.running:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: GitColors.warning,
          ),
        );
      case ProjectOpStatus.stopped:
        return Icon(Icons.stop_circle_outlined, size: 16, color: Colors.grey[400]);
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
