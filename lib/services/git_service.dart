import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/git_models.dart';
import 'auth_service.dart';
import 'settings_service.dart';

class GitService extends ChangeNotifier {
  GitService({
    SettingsService? settings,
    AuthService? authService,
  })  : _settings = settings ?? SettingsService(),
        _authService = authService;

  static const String _defaultProjectName = 'vibe-code-mobile';

  final SettingsService _settings;
  final AuthService? _authService;

  bool _busy = false;
  bool get isBusy => _busy;

  void _log(String message) {
    debugPrint('[GitService] $message');
  }

  Future<String> _effectiveProjectName(String? projectName) async {
    if (projectName != null && projectName.trim().isNotEmpty) {
      return projectName.trim();
    }
    final selected = await _settings.getSelectedProjectName();
    if (selected != null && selected.trim().isNotEmpty) {
      return selected.trim();
    }
    return _defaultProjectName;
  }

  Future<GitSummary> getSummary() async {
    final response = await _get('/vibe/git/summary');
    if (!response.success) throw Exception(response.message);
    final data = _payloadAsMap(response.details);
    return GitSummary(
      branch: _readString(data, ['branch', 'current_branch'], fallback: 'main'),
      aheadCount: _readInt(data, ['ahead_count', 'ahead'], fallback: 0),
      behindCount: _readInt(data, ['behind_count', 'behind'], fallback: 0),
      changedFileCount: _readInt(
        data,
        ['changed_file_count', 'changed_files_count', 'changed_files'],
        fallback: 0,
      ),
      runningTaskCount: _readInt(
        data,
        ['running_task_count', 'running_tasks_count', 'running_tasks'],
        fallback: 0,
      ),
    );
  }

  Future<GitRunStatus> getRunStatus() async {
    final response = await _get('/vibe/git/project/run/status');
    if (!response.success) throw Exception(response.message);
    final payload = _payload(response.details);
    if (payload is Map<String, dynamic>) {
      final taskList = _readList(payload, ['tasks', 'items']);
      final tasks = taskList
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => GitRunTask(
              taskName:
                  _readString(item, ['task_name', 'name'], fallback: 'task'),
              command: _nullableString(item['command']),
              status: _nullableString(item['status']),
              pid: _nullableInt(item['pid']),
            ),
          )
          .toList();
      return GitRunStatus(
        runningTaskCount: _readInt(
          payload,
          ['running_task_count', 'count', 'running_count'],
          fallback: tasks.length,
        ),
        tasks: tasks,
      );
    }

    return GitRunStatus(runningTaskCount: 0, tasks: const []);
  }

  Future<GitOperationResult> startRun({
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);
    return _post(
      '/vibe/git/project/run/start',
      body: {'project_name': effectiveProjectName},
    );
  }

  Future<GitOperationResult> installDependencies({
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);
    return _post(
      '/vibe/git/project/run/install',
      body: {'project_name': effectiveProjectName},
    );
  }

  Future<GitOperationResult> stopAllRuns({
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);
    return _post(
      '/vibe/git/project/run/stop',
      body: {'project_name': effectiveProjectName},
    );
  }

  Future<GitOperationResult> pull({
    String remote = 'origin',
    String branch = 'main',
    bool rebase = false,
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);
    return _post(
      '/vibe/git/sync/pull',
      body: {
        'project_name': effectiveProjectName,
        'remote': remote,
        'branch': branch,
        'rebase': rebase,
      },
    );
  }

  Future<GitPushSummary> getPushSummary({
    String remote = 'origin',
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);

    final response = await _get(
      '/vibe/git/sync/push/preview',
      query: {
        'project_name': effectiveProjectName,
        'remote': remote,
      },
    );
    if (!response.success) throw Exception(response.message);
    final data = _payloadAsMap(response.details);
    return GitPushSummary(
      branch: _readString(data, ['branch', 'current_branch'], fallback: 'main'),
      aheadCount: _readInt(data, ['ahead_count', 'ahead'], fallback: 0),
      remote: _readString(data, ['remote'], fallback: remote),
      remoteBranch: _nullableString(data['remote_branch']),
    );
  }

  Future<GitOperationResult> push({
    required String branch,
    String remote = 'origin',
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);
    return _post(
      '/vibe/git/sync/push',
      body: {
        'project_name': effectiveProjectName,
        'remote': remote,
        'branch': branch,
      },
    );
  }

  Future<GitOperationResult> commit({
    required String message,
    required List<String> filePaths,
    bool addAll = false,
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);
    return _post(
      '/vibe/git/change/commit',
      body: {
        'project_name': effectiveProjectName,
        'message': message,
        'file_paths': filePaths,
        'add_all': addAll,
      },
    );
  }

  Future<String> generateCommitMessage({
    String? projectName,
    List<String>? filePaths,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);

    final response = await _post(
      '/vibe/git/change/commit/generate-message',
      body: {
        'project_name': effectiveProjectName,
        if (filePaths != null && filePaths.isNotEmpty) 'file_paths': filePaths,
      },
    );
    if (!response.success) throw Exception(response.message);

    final data = _payloadAsMap(response.details);
    final message =
        _readOptionalString(data, const ['message', 'commit_message', 'msg']);
    if (message != null && message.trim().isNotEmpty) {
      return message.trim();
    }

    final payload = _payload(response.details);
    if (payload is String && payload.trim().isNotEmpty) return payload.trim();
    throw Exception('未获取到 commit message');
  }

  Future<List<GitCommit>> getResetCandidates({
    int limit = 20,
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);

    final response = await _get(
      '/vibe/git/change/reset/candidates',
      query: {
        'project_name': effectiveProjectName,
        'limit': '$limit',
      },
    );
    if (!response.success) throw Exception(response.message);
    return _parseCommitList(response.details);
  }

  Future<GitOperationResult> reset({
    required String hash,
    required String mode,
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);
    final primary = await _post(
      '/vibe/git/change/reset',
      body: {
        'project_name': effectiveProjectName,
        'commit_hash': hash,
        'mode': mode,
      },
    );
    if (primary.success) return primary;

    final msg = primary.message.toLowerCase();
    final likelyFieldMismatch = msg.contains('revision') ||
        msg.contains('commit_hash') ||
        msg.contains('hash');
    if (!likelyFieldMismatch) return primary;

    final fallback = await _post(
      '/vibe/git/change/reset',
      body: {
        'project_name': effectiveProjectName,
        'revision': hash,
        'mode': mode,
      },
    );
    return fallback.success ? fallback : primary;
  }

  Future<GitOperationResult> stash({
    String message = 'wip',
    bool includeUntracked = true,
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);
    return _post(
      '/vibe/git/advanced/stash',
      body: {
        'project_name': effectiveProjectName,
        'message': message,
        'include_untracked': includeUntracked,
      },
    );
  }

  Future<GitOperationResult> stashPop({
    String? stashRef,
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);
    return _post(
      '/vibe/git/advanced/stash/pop',
      body: {
        'project_name': effectiveProjectName,
        if (stashRef != null && stashRef.isNotEmpty) 'stash_ref': stashRef,
      },
    );
  }

  Future<List<String>> getBranches({
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);

    final response = await _get(
      '/vibe/git/advanced/branches',
      query: {'project_name': effectiveProjectName},
    );
    if (!response.success) throw Exception(response.message);
    final payload = _payload(response.details);
    if (payload is List) return _parseBranchNames(payload);
    if (payload is Map<String, dynamic>) {
      final items = _readList(payload, ['branches', 'items']);
      return _parseBranchNames(items);
    }
    return <String>[];
  }

  Future<GitOperationResult> checkout({
    required String branch,
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);
    return _post(
      '/vibe/git/advanced/checkout',
      body: {
        'project_name': effectiveProjectName,
        'branch': branch,
      },
    );
  }

  Future<List<GitCommit>> log({
    int limit = 20,
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);

    final response = await _get(
      '/vibe/git/advanced/log',
      query: {
        'project_name': effectiveProjectName,
        'limit': '$limit',
      },
    );
    if (!response.success) throw Exception(response.message);
    return _parseCommitList(response.details);
  }

  Future<GitWorktreeStatus> status({
    String? projectName,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);

    final response = await _get(
      '/vibe/git/worktree/status',
      query: {'project_name': effectiveProjectName},
    );
    if (!response.success) throw Exception(response.message);

    final payload = _payload(response.details);
    if (payload is List) {
      return GitWorktreeStatus(files: _parseWorktreeFiles(payload));
    }

    if (payload is Map<String, dynamic>) {
      final filesRaw = _readList(payload, ['files', 'items']);
      final files = _parseWorktreeFiles(filesRaw);
      final stats = <String, int>{};
      final statsRaw = payload['stats'] ?? payload['counts'];
      if (statsRaw is Map<String, dynamic>) {
        for (final entry in statsRaw.entries) {
          stats[entry.key] = _nullableInt(entry.value) ?? 0;
        }
      }
      return GitWorktreeStatus(files: files, counts: stats);
    }

    return GitWorktreeStatus(files: const []);
  }

  Future<GitOperationResult> discardAllChanges({
    String? projectName,
    bool includeUntracked = true,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);
    return _post(
      '/vibe/git/worktree/discard',
      body: {
        'project_name': effectiveProjectName,
        'file_paths': <String>[],
        'include_untracked': includeUntracked,
      },
    );
  }

  Future<GitOperationResult> discardFileChanges({
    required String filePath,
    String? projectName,
    bool includeUntracked = true,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);
    return _post(
      '/vibe/git/worktree/discard',
      body: {
        'project_name': effectiveProjectName,
        'file_paths': [filePath],
        'include_untracked': includeUntracked,
      },
    );
  }

  Future<GitFileDiff> getFileDiff({
    required String filePath,
    String? projectName,
    bool staged = false,
    int contextLines = 3,
  }) async {
    final effectiveProjectName = await _effectiveProjectName(projectName);

    final response = await _post(
      '/vibe/git/worktree/view-changes',
      body: {
        'project_name': effectiveProjectName,
        'file_paths': [filePath],
        'staged': staged,
        'context_lines': contextLines,
      },
    );
    if (!response.success) throw Exception(response.message);
    return _parseViewChangesDiff(response.details, filePath: filePath);
  }

  Future<GitOperationResult> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    return _request(method: 'GET', path: path, query: query);
  }

  Future<GitOperationResult> _post(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    return _request(method: 'POST', path: path, body: body);
  }

  Future<GitOperationResult> _request({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final baseUrl = await _settings.getGitBaseUrl();
    final repoPath = await _settings.getGitRepoPath();
    final token =
        await _authService?.getValidToken() ?? await _settings.getGitToken();
    final startedAt = DateTime.now();

    if (baseUrl == null || baseUrl.isEmpty) {
      _log('$method $path blocked: git base url missing');
      return GitOperationResult(
        success: false,
        message: 'Git backend not configured.',
        details: 'Set Git base URL in settings.',
      );
    }

    final queryMap = <String, String>{
      ...?query,
      if (repoPath != null && repoPath.isNotEmpty) 'repo_path': repoPath,
    };
    final requestBody = <String, dynamic>{...?body};

    _log(
      '$method $path start '
      'query=${queryMap.isEmpty ? '{}' : jsonEncode(queryMap)} '
      'body=${method == 'POST' ? jsonEncode(requestBody) : '{}'} '
      'auth=${(token != null && token.isNotEmpty) ? 'Bearer' : 'none'}',
    );

    _busy = true;
    notifyListeners();

    try {
      final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters: queryMap.isEmpty ? null : queryMap,
      );
      late final http.Response response;
      if (method == 'GET') {
        response = await http.get(
          uri,
          headers: {
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
        );
      } else {
        response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
          body: jsonEncode(requestBody),
        );
      }

      final payload = _safeDecode(response.body);
      final httpSuccess =
          response.statusCode >= 200 && response.statusCode < 300;
      final businessSuccess = _isBusinessSuccess(payload);
      final success = httpSuccess && businessSuccess;
      final message = _extractMessage(payload) ??
          (success ? 'Operation succeeded' : 'Git operation failed.');

      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      _log(
        '$method $path done status=${response.statusCode} '
        'success=$success '
        'elapsed=${elapsedMs}ms body=${_truncate(response.body)}',
      );

      return GitOperationResult(
        success: success,
        message: message,
        details: response.body,
      );
    } catch (error) {
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      _log('$method $path exception after ${elapsedMs}ms: $error');
      return GitOperationResult(
          success: false, message: 'Network error.', details: error.toString());
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  List<GitCommit> _parseCommitList(String? raw) {
    final payload = _payload(raw);
    final list = payload is List
        ? payload
        : payload is Map<String, dynamic>
            ? _readList(payload, ['commits', 'items', 'candidates'])
            : const [];
    return list.whereType<Map<String, dynamic>>().map(_parseCommit).toList();
  }

  GitCommit _parseCommit(Map<String, dynamic> item) {
    final nestedCommit = item['commit'];
    final commitMap = nestedCommit is Map<String, dynamic>
        ? nestedCommit
        : const <String, dynamic>{};
    final merged = <String, dynamic>{...commitMap, ...item};

    final hash = _readString(
      merged,
      [
        'hash',
        'commit_hash',
        'revision',
        'sha',
        'oid',
        'id',
        'full_hash',
        'commit_id',
        'short_hash',
        'short_sha',
        'abbrev_hash',
      ],
      fallback: 'unknown',
    );
    final message = _readString(
      merged,
      ['message', 'subject', 'title', 'summary'],
      fallback: '',
    );
    final dateStr = _nullableString(merged['date']) ??
        _nullableString(merged['commit_date']) ??
        _nullableString(merged['timestamp']) ??
        _nullableString(merged['committed_at']) ??
        _nullableString(merged['commit_time']);
    return GitCommit(
      hash: hash,
      message: message,
      date: _parseDate(dateStr),
      author: _nullableString(merged['author']) ??
          _nullableString(merged['author_name']) ??
          _nullableString(merged['committer']),
    );
  }

  List<GitWorktreeFile> _parseWorktreeFiles(List<dynamic> raw) {
    return raw
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final path = _readString(item, ['path', 'file_path'], fallback: '');
          final statusCode =
              _readString(item, ['status', 'status_code'], fallback: 'M');
          return GitWorktreeFile(path: path, statusCode: statusCode);
        })
        .where((item) => item.path.isNotEmpty)
        .toList();
  }

  List<String> _parseBranchNames(List<dynamic> raw) {
    final names = <String>[];
    for (final item in raw) {
      if (item is String) {
        final value = item.trim();
        if (value.isNotEmpty) names.add(value);
        continue;
      }
      if (item is Map<String, dynamic>) {
        final value = _readOptionalString(
          item,
          const ['name', 'branch', 'branch_name', 'ref', 'display_name'],
        );
        if (value != null && value.trim().isNotEmpty) {
          names.add(value.trim());
        }
      }
    }
    return names.toSet().toList();
  }

  GitFileDiff _parseFileDiff(String? raw, {required String filePath}) {
    final payload = _payload(raw);
    if (payload is String) {
      return GitFileDiff(path: filePath, patch: payload);
    }
    if (payload is Map<String, dynamic>) {
      final content = payload['content'];
      final contentMap =
          content is Map<String, dynamic> ? content : const <String, dynamic>{};
      final merged = <String, dynamic>{...payload, ...contentMap};
      return GitFileDiff(
        path: _readString(merged, ['path', 'file_path'], fallback: filePath),
        beforeContent: _readOptionalString(
          merged,
          const [
            'before_content',
            'before',
            'old_content',
            'original',
            'content_before'
          ],
        ),
        afterContent: _readOptionalString(
          merged,
          const [
            'after_content',
            'after',
            'new_content',
            'modified',
            'content_after'
          ],
        ),
        patch: _readOptionalString(
            merged, const ['patch', 'diff', 'unified_diff']),
      );
    }
    return GitFileDiff(path: filePath);
  }

  GitFileDiff _parseViewChangesDiff(String? raw, {required String filePath}) {
    final payload = _payload(raw);
    if (payload is List) {
      for (final item in payload.whereType<Map<String, dynamic>>()) {
        final path = _readString(item, ['path', 'file_path'], fallback: '');
        if (path == filePath) return _parseViewChangeItem(item, filePath);
      }
      Map<String, dynamic>? first;
      for (final item in payload.whereType<Map<String, dynamic>>()) {
        first = item;
        break;
      }
      if (first != null) return _parseViewChangeItem(first, filePath);
      return GitFileDiff(path: filePath);
    }

    if (payload is Map<String, dynamic>) {
      final directPath = _readOptionalString(
        payload,
        const ['path', 'file_path'],
      );
      if (directPath != null || payload.containsKey('diff')) {
        return _parseViewChangeItem(payload, filePath);
      }

      final items = _readList(payload, const ['changes', 'files', 'items']);
      for (final item in items.whereType<Map<String, dynamic>>()) {
        final path = _readString(item, ['path', 'file_path'], fallback: '');
        if (path == filePath) return _parseViewChangeItem(item, filePath);
      }
      Map<String, dynamic>? first;
      for (final item in items.whereType<Map<String, dynamic>>()) {
        first = item;
        break;
      }
      if (first != null) return _parseViewChangeItem(first, filePath);
    }

    // Backward compatibility: if backend still returns old /worktree/diff shape.
    return _parseFileDiff(raw, filePath: filePath);
  }

  GitFileDiff _parseViewChangeItem(
    Map<String, dynamic> item,
    String fallbackPath,
  ) {
    final path =
        _readString(item, const ['path', 'file_path'], fallback: fallbackPath);
    final patch = _readOptionalString(item, const ['diff', 'patch']);
    final before = _readOptionalString(
      item,
      const ['original_content', 'before_content', 'before', 'old_content'],
    );
    final after = _readOptionalString(
      item,
      const ['current_content', 'after_content', 'after', 'new_content'],
    );
    return GitFileDiff(
      path: path,
      beforeContent: before,
      afterContent: after,
      patch: patch,
    );
  }

  dynamic _payload(String? raw) {
    final decoded = _safeDecode(raw);
    if (decoded is Map<String, dynamic>) {
      for (final key in const ['data', 'result', 'payload']) {
        final value = decoded[key];
        if (value != null) return value;
      }
    }
    return decoded;
  }

  Map<String, dynamic> _payloadAsMap(String? raw) {
    final payload = _payload(raw);
    if (payload is Map<String, dynamic>) return payload;
    return <String, dynamic>{};
  }

  dynamic _safeDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  String? _extractMessage(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      for (final key in const ['message', 'msg', 'detail', 'error']) {
        final value = payload[key];
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  List<dynamic> _readList(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is List) return value;
    }
    return const [];
  }

  String _readString(Map<String, dynamic> map, List<String> keys,
      {required String fallback}) {
    for (final key in keys) {
      final value = _nullableString(map[key]);
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }

  String? _readOptionalString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = _nullableString(map[key]);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  int _readInt(Map<String, dynamic> map, List<String> keys,
      {required int fallback}) {
    for (final key in keys) {
      final value = _nullableInt(map[key]);
      if (value != null) return value;
    }
    return fallback;
  }

  int? _nullableInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String? _nullableString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  DateTime _parseDate(String? value) {
    if (value == null || value.isEmpty) return DateTime.now();
    return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
  }

  bool _isBusinessSuccess(dynamic payload) {
    if (payload is! Map<String, dynamic>) return true;
    final code = _nullableInt(payload['code']);
    if (code == null) return true;
    return code == 200 || code == 0;
  }

  String _truncate(String value, {int max = 500}) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}...';
  }
}
