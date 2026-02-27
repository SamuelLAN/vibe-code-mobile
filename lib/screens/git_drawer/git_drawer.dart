import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/colors.dart';
import '../../../models/git_models.dart';
import '../../../services/git_service.dart';
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

  GitSummary? _summary;
  GitPushSummary? _pushPreview;
  GitRunStatus _runStatus = GitRunStatus(runningTaskCount: 0, tasks: []);
  GitWorktreeStatus _worktree = GitWorktreeStatus(files: const []);
  List<String> _branches = const [];
  List<GitCommit> _logCommits = const [];
  List<GitCommit> _resetCandidates = const [];
  bool _initialLoading = true;
  bool _worktreeActionLoading = false;

  String? _toastMessage;
  Color? _toastColor;
  bool _showingToast = false;

  GitService get _git => context.read<GitService>();

  @override
  void initState() {
    super.initState();
    unawaited(_refreshSliderData(initial: true));
  }

  Future<void> _refreshSliderData({bool initial = false}) async {
    try {
      final results = await Future.wait<dynamic>([
        _git.getSummary(),
        _git.getRunStatus(),
        _git.status(),
        _git.getPushSummary(),
      ]);

      if (!mounted) return;
      setState(() {
        _summary = results[0] as GitSummary;
        _runStatus = results[1] as GitRunStatus;
        _worktree = results[2] as GitWorktreeStatus;
        _pushPreview = results[3] as GitPushSummary;
        if (_runStatus.runningTaskCount > 0) {
          _npmStartStatus = ProjectOpStatus.running;
        } else if (_npmStartStatus == ProjectOpStatus.running) {
          _npmStartStatus = ProjectOpStatus.stopped;
        }
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _initialLoading = false);
      _showToast('加载 Git 状态失败: $e', color: GitColors.error);
    }
  }

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

  Future<void> _runGitOperation({
    required Future<GitOperationResult> Function() action,
    required GitOpStatus currentStatus,
    required void Function(GitOpStatus) setStatus,
    required String successFallback,
    bool refreshAfter = true,
  }) async {
    HapticFeedback.mediumImpact();
    setStatus(GitOpStatus.loading);
    final result = await action();
    if (!mounted) return;

    if (result.success) {
      setStatus(GitOpStatus.success);
      _showToast(result.message.isNotEmpty ? result.message : successFallback);
      if (refreshAfter) {
        unawaited(_refreshSliderData());
      }
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) setStatus(GitOpStatus.idle);
      });
      return;
    }

    setStatus(GitOpStatus.error);
    _showToast(result.message, color: GitColors.error);
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setStatus(GitOpStatus.idle);
    });
  }

  Future<void> _runProjectOperation({
    required Future<GitOperationResult> Function() action,
    required ProjectOpStatus successStatus,
    required void Function(ProjectOpStatus) setStatus,
    required String successFallback,
    bool refreshAfter = true,
  }) async {
    HapticFeedback.mediumImpact();
    setStatus(ProjectOpStatus.running);
    final result = await action();
    if (!mounted) return;

    if (result.success) {
      setStatus(successStatus);
      _showToast(result.message.isNotEmpty ? result.message : successFallback);
      if (refreshAfter) {
        await _refreshSliderData();
      }
      if (successStatus != ProjectOpStatus.running) {
        Future.delayed(const Duration(milliseconds: 1800), () {
          if (mounted) setStatus(ProjectOpStatus.idle);
        });
      }
      return;
    }

    setStatus(ProjectOpStatus.stopped);
    _showToast(result.message, color: GitColors.error);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final summary = _summary;
    final currentBranch = summary?.branch ?? 'main';
    final commitsAhead = _pushPreview?.aheadCount ?? summary?.aheadCount ?? 0;
    final running = _runStatus.runningTaskCount > 0;

    return Drawer(
      backgroundColor:
          isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(theme, isDark, currentBranch, summary),
                Expanded(
                  child: _initialLoading
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: _refreshSliderData,
                          child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children: [
                              const SizedBox(height: 8),
                              _buildSectionTitle('项目运行'),
                              _buildProjectOpButton(
                                icon: Icons.play_arrow_rounded,
                                label: 'npm start',
                                sublabel: running
                                    ? '${_runStatus.runningTaskCount} 个任务运行中'
                                    : '启动开发服务器',
                                status: _npmStartStatus,
                                accentColor: GitColors.success,
                                isRunning: running,
                                onPress: () => _runProjectOperation(
                                  action: () => _git.startRun(
                                      command: 'npm start',
                                      taskName: 'npm start'),
                                  successStatus: ProjectOpStatus.running,
                                  successFallback: '开发服务器已启动',
                                  setStatus: (s) =>
                                      setState(() => _npmStartStatus = s),
                                ),
                                onStop: () => _runProjectOperation(
                                  action: _git.stopAllRuns,
                                  successStatus: ProjectOpStatus.stopped,
                                  successFallback: '已停止所有服务',
                                  setStatus: (s) =>
                                      setState(() => _npmStartStatus = s),
                                ),
                              ),
                              _buildProjectOpButton(
                                icon: Icons.download_rounded,
                                label: 'npm install',
                                sublabel: '安装项目依赖',
                                status: _npmInstallStatus,
                                accentColor: GitColors.commit,
                                onPress: () => _runProjectOperation(
                                  action: _git.installDependencies,
                                  successStatus: ProjectOpStatus.idle,
                                  successFallback: '依赖安装完成',
                                  setStatus: (s) =>
                                      setState(() => _npmInstallStatus = s),
                                ),
                              ),
                              _buildProjectOpButton(
                                icon: Icons.stop_rounded,
                                label: 'Stop',
                                sublabel: '停止所有运行中的服务',
                                status: ProjectOpStatus.stopped,
                                accentColor: GitColors.error,
                                onPress: () => _runProjectOperation(
                                  action: _git.stopAllRuns,
                                  successStatus: ProjectOpStatus.stopped,
                                  successFallback: '已停止所有服务',
                                  setStatus: (s) =>
                                      setState(() => _npmStartStatus = s),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildSectionTitle('同步'),
                              _buildGitOpButton(
                                icon: Icons.download_rounded,
                                label: 'Pull',
                                sublabel:
                                    '从 origin/${summary?.branch ?? 'main'} 拉取并合并',
                                status: _pullStatus,
                                accentColor: GitColors.pull,
                                onPress: () => _runGitOperation(
                                  action: () => _git.pull(
                                      branch: summary?.branch ?? 'main'),
                                  currentStatus: _pullStatus,
                                  successFallback: '拉取完成',
                                  setStatus: (s) =>
                                      setState(() => _pullStatus = s),
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
                                sublabel: '${_worktree.files.length} 个文件已更改',
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
                                onPress: () => _runGitOperation(
                                  action: _git.stash,
                                  currentStatus: _stashStatus,
                                  successFallback: '更改已暂存',
                                  setStatus: (s) =>
                                      setState(() => _stashStatus = s),
                                ),
                              ),
                              _buildGitOpButton(
                                icon: Icons.unarchive_rounded,
                                label: 'Stash Pop',
                                sublabel: '恢复暂存的更改',
                                status: _stashPopStatus,
                                accentColor: GitColors.stash,
                                onPress: () => _runGitOperation(
                                  action: _git.stashPop,
                                  currentStatus: _stashPopStatus,
                                  successFallback: '更改已恢复',
                                  setStatus: (s) =>
                                      setState(() => _stashPopStatus = s),
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

  Widget _buildHeader(
      ThemeData theme, bool isDark, String currentBranch, GitSummary? summary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
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
                Icon(Icons.account_tree_rounded,
                    size: 14, color: theme.colorScheme.primary),
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
              '↑${summary?.aheadCount ?? 0}${(summary?.behindCount ?? 0) > 0 ? ' ↓${summary!.behindCount}' : ''}',
              style: const TextStyle(
                color: GitColors.success,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: _refreshSliderData,
            tooltip: '刷新',
          ),
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
                  color: Colors.white, borderRadius: BorderRadius.circular(12)),
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
                        Text(label,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 1),
                        Text(
                          sublabel,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
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
              strokeWidth: 2, color: GitColors.warning),
        );
      case GitOpStatus.success:
        return const Icon(Icons.check, size: 16, color: GitColors.success);
      case GitOpStatus.error:
        return const Icon(Icons.warning_rounded,
            size: 16, color: GitColors.error);
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
    final showLoading = status == ProjectOpStatus.running && !isRunning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: showLoading
              ? null
              : (isRunning && onStop != null ? onStop : onPress),
          child: Opacity(
            opacity: showLoading ? 0.6 : 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12)),
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
                        Text(label,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 1),
                        Text(
                          sublabel,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _buildProjectStatusIcon(status,
                      isRunning: isRunning, showLoading: showLoading),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProjectStatusIcon(
    ProjectOpStatus status, {
    required bool isRunning,
    required bool showLoading,
  }) {
    if (isRunning) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: GitColors.success, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          const Text(
            '运行中',
            style: TextStyle(
                fontSize: 12,
                color: GitColors.success,
                fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    if (showLoading) {
      return const SizedBox(
        width: 16,
        height: 16,
        child:
            CircularProgressIndicator(strokeWidth: 2, color: GitColors.warning),
      );
    }
    switch (status) {
      case ProjectOpStatus.stopped:
        return Icon(Icons.stop_circle_outlined,
            size: 16, color: Colors.grey[400]);
      case ProjectOpStatus.idle:
      case ProjectOpStatus.running:
        return Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]);
    }
  }

  Widget _buildStatusCard(ThemeData theme, bool isDark) {
    final files = _worktree.files;
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
          Row(
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
              const Spacer(),
              if (files.isNotEmpty)
                TextButton.icon(
                  onPressed: _worktreeActionLoading
                      ? null
                      : () => _discardAllWorktreeChanges(context),
                  style: TextButton.styleFrom(
                    foregroundColor: GitColors.error,
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                  label: const Text(
                    'Discard All Changes',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          if (_worktreeActionLoading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: 10),
          if (files.isEmpty)
            Text('工作树干净',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ...files.take(8).map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _worktreeActionLoading
                        ? null
                        : () => _showWorktreeFileActions(context, f),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _statusColor(f.statusCode),
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
                            f.statusCode.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _statusColor(f.statusCode),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _worktreeActionLoading
                                ? null
                                : () => _discardSingleFile(context, f),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: GitColors.error,
                              minimumSize: const Size(0, 28),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                            ),
                            child: const Text(
                              'Discard',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )),
          if (files.length > 8) ...[
            const SizedBox(height: 6),
            Text(
              '还有 ${files.length - 8} 个文件',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String code) {
    switch (code.toUpperCase()) {
      case 'D':
        return GitColors.deleted;
      case 'A':
      case '?':
        return GitColors.added;
      default:
        return GitColors.modified;
    }
  }

  Future<void> _discardAllWorktreeChanges(BuildContext context) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Discard All Changes',
      message: '这会丢弃所有未提交改动。该操作不可撤销，是否继续？',
      confirmLabel: '确认全部丢弃',
      destructive: true,
    );
    if (confirmed != true) return;

    setState(() => _worktreeActionLoading = true);
    final result = await _git.discardAllChanges();
    if (!mounted) return;
    setState(() => _worktreeActionLoading = false);
    if (result.success) {
      _showToast(result.message.isNotEmpty ? result.message : '已丢弃全部改动');
      unawaited(_refreshSliderData());
      return;
    }
    _showToast(result.message, color: GitColors.error);
  }

  Future<void> _discardSingleFile(
    BuildContext context,
    GitWorktreeFile file,
  ) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Discard changes',
      message: '将丢弃 `${file.path}` 的改动，是否继续？',
      confirmLabel: '确认丢弃',
      destructive: true,
    );
    if (confirmed != true) return;

    setState(() => _worktreeActionLoading = true);
    final result = await _git.discardFileChanges(filePath: file.path);
    if (!mounted) return;
    setState(() => _worktreeActionLoading = false);
    if (result.success) {
      _showToast(
          result.message.isNotEmpty ? result.message : '已丢弃 ${file.path} 的改动');
      unawaited(_refreshSliderData());
      return;
    }
    _showToast(result.message, color: GitColors.error);
  }

  Future<void> _showWorktreeFileActions(
    BuildContext context,
    GitWorktreeFile file,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    file.path,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '状态: ${file.statusCode.toUpperCase()}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _viewFileChanges(context, file);
                    },
                    icon: const Icon(Icons.visibility_rounded, size: 18),
                    label: const Text('View changes'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: GitColors.error,
                    ),
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _discardSingleFile(context, file);
                    },
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    label: const Text('Discard changes'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _viewFileChanges(
      BuildContext context, GitWorktreeFile file) async {
    try {
      setState(() => _worktreeActionLoading = true);
      final diff = await _git.getFileDiff(filePath: file.path);
      if (!mounted) return;
      setState(() => _worktreeActionLoading = false);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        enableDrag: true,
        backgroundColor: Colors.transparent,
        builder: (modalContext) => FractionallySizedBox(
          heightFactor: 0.9,
          child: FileDiffModal(diff: diff),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _worktreeActionLoading = false);
      _showToast('加载文件改动失败: $e', color: GitColors.error);
    }
  }

  Future<bool?> _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: destructive
                  ? GitColors.error
                  : Theme.of(context).colorScheme.primary,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
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
              _toastColor == GitColors.error
                  ? Icons.error_outline
                  : Icons.check_circle_outline,
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
                    fontWeight: FontWeight.w500),
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
        files: _worktree.files,
        onGenerateMessage: (filePaths) => _git.generateCommitMessage(
          filePaths: filePaths,
        ),
        onConfirm: (message, filePaths, addAll) async {
          Navigator.pop(context);
          await _runGitOperation(
            action: () => _git.commit(
                message: message, filePaths: filePaths, addAll: addAll),
            currentStatus: _commitStatus,
            successFallback: '提交成功',
            setStatus: (s) => setState(() => _commitStatus = s),
          );
        },
      ),
    );
  }

  Future<void> _showResetModal(BuildContext context) async {
    if (_resetCandidates.isEmpty) {
      try {
        final candidates = await _git.getResetCandidates();
        if (!mounted) return;
        setState(() => _resetCandidates = candidates);
      } catch (e) {
        if (!mounted) return;
        _showToast('加载重置候选失败: $e', color: GitColors.error);
        return;
      }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: ResetModal(
          commits: _resetCandidates,
          onConfirm: (commit, type) async {
            Navigator.pop(context);
            await _runGitOperation(
              action: () => _git.reset(hash: commit.hash, mode: type),
              currentStatus: _resetStatus,
              successFallback: '已重置到 ${commit.shortHash}',
              setStatus: (s) => setState(() => _resetStatus = s),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showPushModal(BuildContext context) async {
    try {
      final preview = await _git.getPushSummary();
      if (!mounted) return;
      setState(() => _pushPreview = preview);
    } catch (e) {
      if (!mounted) return;
      _showToast('获取推送预检查失败: $e', color: GitColors.error);
      return;
    }

    final preview = _pushPreview ??
        GitPushSummary(branch: _summary?.branch ?? 'main', aheadCount: 0);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PushModal(
        branch: preview.branch,
        remote: preview.remote,
        aheadCount: preview.aheadCount,
        onConfirm: () async {
          Navigator.pop(context);
          await _runGitOperation(
            action: () =>
                _git.push(branch: preview.branch, remote: preview.remote),
            currentStatus: _pushStatus,
            successFallback: '推送完成',
            setStatus: (s) => setState(() => _pushStatus = s),
          );
        },
      ),
    );
  }

  Future<void> _showLogModal(BuildContext context) async {
    try {
      final commits = await _git.log();
      if (!mounted) return;
      setState(() => _logCommits = commits);
    } catch (e) {
      if (!mounted) return;
      _showToast('加载日志失败: $e', color: GitColors.error);
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 300),
      ),
      builder: (context) => LogModal(commits: _logCommits),
    );
  }

  Future<void> _showBranchModal(BuildContext context) async {
    try {
      final branches = await _git.getBranches();
      if (!mounted) return;
      setState(() => _branches = branches);
    } catch (e) {
      if (!mounted) return;
      _showToast('加载分支失败: $e', color: GitColors.error);
      return;
    }

    final currentBranch = _summary?.branch ?? 'main';
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BranchModal(
        branches: _branches,
        currentBranch: currentBranch,
        onSelect: (branch) async {
          Navigator.pop(context);
          await _runGitOperation(
            action: () => _git.checkout(branch: branch),
            currentStatus: GitOpStatus.idle,
            successFallback: '已切换到分支 $branch',
            setStatus: (_) {},
          );
        },
      ),
    );
  }
}
