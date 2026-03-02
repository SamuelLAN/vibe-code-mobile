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
  const GitDrawer({
    super.key,
    required this.projectName,
  });

  final String projectName;

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

  ProjectOpStatus _buildStatus = ProjectOpStatus.idle;
  ProjectOpStatus _runDevStatus = ProjectOpStatus.stopped;
  ProjectOpStatus _runPreviewStatus = ProjectOpStatus.stopped;
  ProjectOpStatus _installStatus = ProjectOpStatus.idle;
  ProjectOpStatus _stopDevStatus = ProjectOpStatus.idle;
  ProjectOpStatus _stopPreviewStatus = ProjectOpStatus.idle;
  ProjectOpStatus _npmCommandStatus = ProjectOpStatus.idle;

  GitSummary? _summary;
  GitPushSummary? _pushPreview;
  GitRunStatus _runStatus = GitRunStatus(runningTaskCount: 0, tasks: []);
  GitWorktreeStatus _worktree = GitWorktreeStatus(files: const []);
  List<GitBranchRef> _branches = const [];
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

  @override
  void didUpdateWidget(covariant GitDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectName != widget.projectName) {
      unawaited(_refreshSliderData());
    }
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
        final devRunning = _isTaskRunning('dev');
        final previewRunning = _isTaskRunning('preview');
        if (devRunning) {
          _runDevStatus = ProjectOpStatus.running;
        } else {
          if (_runDevStatus == ProjectOpStatus.running) {
            _runDevStatus = ProjectOpStatus.stopped;
          }
        }
        if (previewRunning) {
          _runPreviewStatus = ProjectOpStatus.running;
        } else {
          if (_runPreviewStatus == ProjectOpStatus.running) {
            _runPreviewStatus = ProjectOpStatus.stopped;
          }
        }
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _initialLoading = false);
      _showToast('Failed to load Git status: $e', color: GitColors.error);
    }
  }

  bool _isTaskRunning(String scriptName) {
    final key = 'npm run $scriptName';
    for (final task in _runStatus.tasks) {
      final command = (task.command ?? '').toLowerCase();
      final taskName = task.taskName.toLowerCase();
      if (command.contains(key) || taskName.contains(key)) {
        return true;
      }
    }
    return false;
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

  Future<void> _runProjectSseOperation({
    required String sheetTitle,
    required Stream<GitSseEvent> stream,
    required void Function(ProjectOpStatus) setStatus,
    required ProjectOpStatus successStatus,
    ProjectOpStatus errorStatus = ProjectOpStatus.idle,
    String successFallback = 'Operation completed',
    String errorFallback = 'Operation failed',
    bool refreshAfter = true,
  }) async {
    HapticFeedback.mediumImpact();
    setStatus(ProjectOpStatus.running);

    final shared = stream.asBroadcastStream();
    var resolved = false;
    final subscription = shared.listen(
      (event) {
        final name = event.name.toLowerCase();
        if (name == 'completed' && !resolved) {
          resolved = true;
          setStatus(successStatus);
          _showToast(_eventMessage(event) ?? successFallback);
          if (refreshAfter) {
            unawaited(_refreshSliderData());
          }
          if (successStatus != ProjectOpStatus.running) {
            Future.delayed(const Duration(milliseconds: 1800), () {
              if (mounted) setStatus(ProjectOpStatus.idle);
            });
          }
        } else if (name == 'error' && !resolved) {
          resolved = true;
          setStatus(errorStatus);
          _showToast(_eventMessage(event) ?? errorFallback,
              color: GitColors.error);
        }
      },
      onDone: () {
        if (resolved || !mounted) return;
        setStatus(ProjectOpStatus.idle);
      },
      onError: (_) {
        if (resolved || !mounted) return;
        setStatus(errorStatus);
      },
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.8,
        child: RunStreamModal(
          title: sheetTitle,
          stream: shared,
        ),
      ),
    );

    await subscription.cancel();
  }

  String? _eventMessage(GitSseEvent event) {
    final data = event.data;
    if (data == null) return null;
    final msg = data['msg']?.toString();
    if (msg != null && msg.trim().isNotEmpty) return msg.trim();
    final line = data['line']?.toString();
    if (line != null && line.trim().isNotEmpty) return line.trim();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final summary = _summary;
    final currentBranch = summary?.branch ?? 'main';
    final commitsAhead = _pushPreview?.aheadCount ?? summary?.aheadCount ?? 0;
    final devRunning = _isTaskRunning('dev');
    final previewRunning = _isTaskRunning('preview');
    final running = devRunning || previewRunning;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      backgroundColor:
          isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(theme, isDark, currentBranch, summary, running),
                Expanded(
                  child: _initialLoading
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: _refreshSliderData,
                          child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children: [
                              const SizedBox(height: 8),
                              _buildSectionTitle('Project run'),
                              _buildProjectOpButton(
                                icon: Icons.build_rounded,
                                label: 'build',
                                sublabel: 'Run project build',
                                status: _buildStatus,
                                accentColor: GitColors.warning,
                                onPress: () => _runProjectSseOperation(
                                  sheetTitle: 'build',
                                  stream: _git.streamRunBuild(),
                                  successStatus: ProjectOpStatus.idle,
                                  successFallback: 'Build completed',
                                  setStatus: (s) =>
                                      setState(() => _buildStatus = s),
                                ),
                              ),
                              _buildProjectOpButton(
                                icon: Icons.download_rounded,
                                label: 'install',
                                sublabel: 'Install project dependencies',
                                status: _installStatus,
                                accentColor: GitColors.commit,
                                onPress: () => _runProjectSseOperation(
                                  sheetTitle: 'install',
                                  stream: _git.streamInstallDependencies(),
                                  successStatus: ProjectOpStatus.idle,
                                  successFallback: 'Dependencies installed',
                                  setStatus: (s) =>
                                      setState(() => _installStatus = s),
                                ),
                              ),
                              _buildProjectOpButton(
                                icon: Icons.play_arrow_rounded,
                                label: 'run dev',
                                sublabel: devRunning
                                    ? 'dev service is running'
                                    : 'Start development server',
                                status: _runDevStatus,
                                accentColor: GitColors.success,
                                isRunning: devRunning,
                                onPress: () => _runProjectSseOperation(
                                  sheetTitle: 'run dev',
                                  stream: _git.streamRunDev(),
                                  successStatus: ProjectOpStatus.running,
                                  successFallback: 'Development server started',
                                  setStatus: (s) =>
                                      setState(() => _runDevStatus = s),
                                ),
                                onStop: () => _runProjectSseOperation(
                                  sheetTitle: 'stop dev',
                                  stream: _git.streamStopDev(),
                                  successStatus: ProjectOpStatus.stopped,
                                  successFallback: 'Stopped dev service',
                                  setStatus: (s) =>
                                      setState(() => _runDevStatus = s),
                                ),
                              ),
                              _buildProjectOpButton(
                                icon: Icons.slideshow_rounded,
                                label: 'run preview',
                                sublabel: previewRunning
                                    ? 'preview service is running'
                                    : 'Start preview server',
                                status: _runPreviewStatus,
                                accentColor: GitColors.push,
                                isRunning: previewRunning,
                                onPress: () => _runProjectSseOperation(
                                  sheetTitle: 'run preview',
                                  stream: _git.streamRunPreview(),
                                  successStatus: ProjectOpStatus.running,
                                  successFallback: 'Preview server started',
                                  setStatus: (s) =>
                                      setState(() => _runPreviewStatus = s),
                                ),
                                onStop: () => _runProjectSseOperation(
                                  sheetTitle: 'stop preview',
                                  stream: _git.streamStopPreview(),
                                  successStatus: ProjectOpStatus.stopped,
                                  successFallback: 'Stopped preview service',
                                  setStatus: (s) =>
                                      setState(() => _runPreviewStatus = s),
                                ),
                              ),
                              _buildProjectOpButton(
                                icon: Icons.stop_rounded,
                                label: 'stop dev',
                                sublabel: 'Stop dev service',
                                status: _stopDevStatus,
                                accentColor: GitColors.error,
                                onPress: () => _runProjectSseOperation(
                                  sheetTitle: 'stop dev',
                                  stream: _git.streamStopDev(),
                                  successStatus: ProjectOpStatus.stopped,
                                  successFallback: 'Stopped dev service',
                                  setStatus: (s) =>
                                      setState(() => _stopDevStatus = s),
                                ),
                              ),
                              _buildProjectOpButton(
                                icon: Icons.stop_circle_outlined,
                                label: 'stop preview',
                                sublabel: 'Stop preview service',
                                status: _stopPreviewStatus,
                                accentColor: GitColors.error,
                                onPress: () => _runProjectSseOperation(
                                  sheetTitle: 'stop preview',
                                  stream: _git.streamStopPreview(),
                                  successStatus: ProjectOpStatus.stopped,
                                  successFallback: 'Stopped preview service',
                                  setStatus: (s) =>
                                      setState(() => _stopPreviewStatus = s),
                                ),
                              ),
                              _buildProjectOpButton(
                                icon: Icons.terminal_rounded,
                                label: 'npm command',
                                sublabel: 'Run npm run/install/ci command',
                                status: _npmCommandStatus,
                                accentColor: GitColors.branch,
                                onPress: _runCustomNpmCommand,
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  'Allowed: npm run build/dev/preview/prod/lint/test, npm install, npm ci',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildSectionTitle('Sync'),
                              _buildGitOpButton(
                                icon: Icons.download_rounded,
                                label: 'Pull',
                                sublabel:
                                    'Pull and merge from origin/${summary?.branch ?? 'main'}',
                                status: _pullStatus,
                                accentColor: GitColors.pull,
                                onPress: () => _runGitOperation(
                                  action: () => _git.pull(
                                      branch: summary?.branch ?? 'main'),
                                  currentStatus: _pullStatus,
                                  successFallback: 'Pull completed',
                                  setStatus: (s) =>
                                      setState(() => _pullStatus = s),
                                ),
                              ),
                              _buildGitOpButton(
                                icon: Icons.upload_rounded,
                                label: 'Push',
                                sublabel: '$commitsAhead commits to push',
                                status: _pushStatus,
                                accentColor: GitColors.push,
                                onPress: () => _showPushModal(context),
                              ),
                              const SizedBox(height: 16),
                              _buildSectionTitle('Changes'),
                              _buildGitOpButton(
                                icon: Icons.commit_rounded,
                                label: 'Commit',
                                sublabel:
                                    '${_worktree.files.length} files changed',
                                status: _commitStatus,
                                accentColor: GitColors.commit,
                                onPress: () => _showCommitModal(context),
                              ),
                              _buildGitOpButton(
                                icon: Icons.restore_rounded,
                                label: 'Reset',
                                sublabel: 'Reset to an earlier commit',
                                status: _resetStatus,
                                accentColor: GitColors.reset,
                                onPress: () => _showResetModal(context),
                              ),
                              const SizedBox(height: 16),
                              _buildSectionTitle('Advanced'),
                              _buildGitOpButton(
                                icon: Icons.archive_rounded,
                                label: 'Stash changes',
                                sublabel: 'Save changes for later',
                                status: _stashStatus,
                                accentColor: GitColors.stash,
                                onPress: () => _runGitOperation(
                                  action: _git.stash,
                                  currentStatus: _stashStatus,
                                  successFallback: 'Changes stashed',
                                  setStatus: (s) =>
                                      setState(() => _stashStatus = s),
                                ),
                              ),
                              _buildGitOpButton(
                                icon: Icons.unarchive_rounded,
                                label: 'Stash Pop',
                                sublabel: 'Restore stashed changes',
                                status: _stashPopStatus,
                                accentColor: GitColors.stash,
                                onPress: () => _runGitOperation(
                                  action: _git.stashPop,
                                  currentStatus: _stashPopStatus,
                                  successFallback: 'Changes restored',
                                  setStatus: (s) =>
                                      setState(() => _stashPopStatus = s),
                                ),
                              ),
                              _buildGitOpButton(
                                icon: Icons.history_rounded,
                                label: 'Git Log',
                                sublabel: 'View recent commits',
                                status: GitOpStatus.idle,
                                accentColor: GitColors.log,
                                onPress: () => _showLogModal(context),
                              ),
                              _buildGitOpButton(
                                icon: Icons.account_tree_rounded,
                                label: 'Switch branch',
                                sublabel: 'Current: $currentBranch',
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
    ThemeData theme,
    bool isDark,
    String currentBranch,
    GitSummary? summary,
    bool isRunning,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
      ),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _showBranchModal(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        currentBranch,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isRunning
                  ? GitColors.success.withOpacity(0.12)
                  : (isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: isRunning
                ? const Icon(
                    Icons.play_circle_fill_rounded,
                    size: 14,
                    color: GitColors.success,
                  )
                : Icon(
                    Icons.stop_circle,
                    size: 14,
                    color: Colors.grey[600],
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
            tooltip: 'Refresh',
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
            'running',
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
                'Working tree status',
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
            Text('Working tree clean',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ...files.take(8).map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _worktreeActionLoading
                        ? null
                        : () => _viewFileChanges(context, f),
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
              '${files.length - 8} more files',
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
      message:
          'This will discard all uncommitted changes. This action cannot be undone. Continue?',
      confirmLabel: 'Confirm discard all',
      destructive: true,
    );
    if (confirmed != true) return;

    setState(() => _worktreeActionLoading = true);
    final result = await _git.discardAllChanges();
    if (!mounted) return;
    setState(() => _worktreeActionLoading = false);
    if (result.success) {
      _showToast(
          result.message.isNotEmpty ? result.message : 'All changes discarded');
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
      message: 'This will discard changes in `${file.path}`. Continue?',
      confirmLabel: 'Confirm discard',
      destructive: true,
    );
    if (confirmed != true) return;

    setState(() => _worktreeActionLoading = true);
    final result = await _git.discardFileChanges(filePath: file.path);
    if (!mounted) return;
    setState(() => _worktreeActionLoading = false);
    if (result.success) {
      _showToast(result.message.isNotEmpty
          ? result.message
          : 'Discarded changes in ${file.path}');
      unawaited(_refreshSliderData());
      return;
    }
    _showToast(result.message, color: GitColors.error);
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
      _showToast('Failed to load file changes: $e', color: GitColors.error);
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
            child: const Text('Cancel'),
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
            successFallback: 'Commit successful',
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
        _showToast('Failed to load reset candidates: $e',
            color: GitColors.error);
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
              successFallback: 'Reset to ${commit.shortHash}',
              setStatus: (s) => setState(() => _resetStatus = s),
            );
          },
        ),
      ),
    );
  }

  Future<void> _runCustomNpmCommand() async {
    final input = await _showNpmCommandDialog(context);
    if (input == null || !mounted) return;

    await _runProjectSseOperation(
      sheetTitle: 'npm command',
      stream: _git.streamRunNpmCommand(
        command: input.command,
        timeoutSeconds: input.timeoutSeconds,
      ),
      successStatus: ProjectOpStatus.idle,
      successFallback: 'npm command completed',
      setStatus: (s) => setState(() => _npmCommandStatus = s),
    );
  }

  Future<_NpmCommandInput?> _showNpmCommandDialog(BuildContext context) async {
    final commandController = TextEditingController(text: 'npm run build');
    final timeoutController = TextEditingController(text: '900');

    final result = await showDialog<_NpmCommandInput>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Run npm command'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: commandController,
              decoration: const InputDecoration(
                labelText: 'Command',
                hintText: 'npm run build',
              ),
              autofocus: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: timeoutController,
              decoration: const InputDecoration(
                labelText: 'Timeout (seconds)',
                hintText: '900',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            Text(
              'Only allowed: npm run build/dev/preview/prod/lint/test, npm install, npm ci',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final command = commandController.text.trim();
              if (command.isEmpty) {
                _showToast('Please enter an npm command',
                    color: GitColors.error);
                return;
              }

              final timeoutValue = int.tryParse(timeoutController.text.trim());
              if (timeoutValue == null || timeoutValue <= 0) {
                _showToast('Timeout must be a positive integer',
                    color: GitColors.error);
                return;
              }

              Navigator.pop(
                dialogContext,
                _NpmCommandInput(
                  command: command,
                  timeoutSeconds: timeoutValue,
                ),
              );
            },
            child: const Text('Run'),
          ),
        ],
      ),
    );

    commandController.dispose();
    timeoutController.dispose();
    return result;
  }

  Future<void> _showPushModal(BuildContext context) async {
    try {
      final preview = await _git.getPushSummary();
      if (!mounted) return;
      setState(() => _pushPreview = preview);
    } catch (e) {
      if (!mounted) return;
      _showToast('Failed to get push precheck: $e', color: GitColors.error);
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
            successFallback: 'Push completed',
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
      _showToast('Failed to load log: $e', color: GitColors.error);
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
      final branches = await _git.getBranchRefs();
      if (!mounted) return;
      setState(() => _branches = branches);
    } catch (e) {
      if (!mounted) return;
      _showToast('Failed to load branches: $e', color: GitColors.error);
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
        onCheckout: (branch) async {
          Navigator.pop(context);
          await _runGitOperation(
            action: () => _git.checkout(branch: branch.fullName),
            currentStatus: GitOpStatus.idle,
            successFallback:
                'Switched to branch ${branch.isRemote ? branch.fullName : branch.name}',
            setStatus: (_) {},
          );
        },
        onCreateLocalBranch: (newBranchName, fromBranch) async {
          Navigator.pop(context);
          await _runGitOperation(
            action: () => _git.checkout(
              branch: newBranchName,
              createBranch: true,
              startPoint: fromBranch.fullName,
            ),
            currentStatus: GitOpStatus.idle,
            successFallback: 'Created and switched to branch $newBranchName',
            setStatus: (_) {},
          );
        },
      ),
    );
  }
}

class _NpmCommandInput {
  const _NpmCommandInput({
    required this.command,
    required this.timeoutSeconds,
  });

  final String command;
  final int timeoutSeconds;
}
