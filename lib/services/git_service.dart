import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/git_models.dart';
import 'settings_service.dart';

class GitService extends ChangeNotifier {
  GitService({SettingsService? settings}) : _settings = settings ?? SettingsService();

  static const String _defaultProjectName = 'vibe-code-mobile';

  final SettingsService _settings;

  bool _busy = false;
  bool get isBusy => _busy;

  void _log(String message) {
    debugPrint('[GitService] $message');
  }

  Future<GitSummary> getSummary() async {
    final mock = await _settings.getGitMockMode();
    if (mock) {
      _log('GET /vibe/git/summary -> mock mode enabled');
      return GitSummary(
        branch: 'main',
        aheadCount: 3,
        behindCount: 0,
        changedFileCount: 4,
        runningTaskCount: 1,
      );
    }

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
    final mock = await _settings.getGitMockMode();
    if (mock) {
      _log('GET /vibe/git/project/run/status -> mock mode enabled');
      return GitRunStatus(
        runningTaskCount: 1,
        tasks: [
          GitRunTask(taskName: 'npm start', command: 'npm start', status: 'running'),
        ],
      );
    }

    final response = await _get('/vibe/git/project/run/status');
    if (!response.success) throw Exception(response.message);
    final payload = _payload(response.details);
    if (payload is Map<String, dynamic>) {
      final taskList = _readList(payload, ['tasks', 'items']);
      final tasks = taskList
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => GitRunTask(
              taskName: _readString(item, ['task_name', 'name'], fallback: 'task'),
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
    required String command,
    required String taskName,
    String projectName = _defaultProjectName,
  }) {
    return _post(
      '/vibe/git/project/run/start',
      body: {
        'project_name': projectName,
        'command': command,
        'task_name': taskName,
      },
    );
  }

  Future<GitOperationResult> installDependencies({
    String projectName = _defaultProjectName,
  }) {
    return _post(
      '/vibe/git/project/run/install',
      body: {'project_name': projectName},
    );
  }

  Future<GitOperationResult> stopAllRuns({
    String projectName = _defaultProjectName,
  }) {
    return _post(
      '/vibe/git/project/run/stop',
      body: {'project_name': projectName},
    );
  }

  Future<GitOperationResult> pull({
    String remote = 'origin',
    String branch = 'main',
    bool rebase = false,
    String projectName = _defaultProjectName,
  }) {
    return _post(
      '/vibe/git/sync/pull',
      body: {
        'project_name': projectName,
        'remote': remote,
        'branch': branch,
        'rebase': rebase,
      },
    );
  }

  Future<GitPushSummary> getPushSummary({
    String remote = 'origin',
    String projectName = _defaultProjectName,
  }) async {
    final mock = await _settings.getGitMockMode();
    if (mock) {
      _log('GET /vibe/git/sync/push/preview -> mock mode enabled');
      return GitPushSummary(branch: 'main', aheadCount: 2, remote: remote);
    }

    final response = await _get(
      '/vibe/git/sync/push/preview',
      query: {
        'project_name': projectName,
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
    String projectName = _defaultProjectName,
  }) {
    return _post(
      '/vibe/git/sync/push',
      body: {
        'project_name': projectName,
        'remote': remote,
        'branch': branch,
      },
    );
  }

  Future<GitOperationResult> commit({
    required String message,
    required List<String> filePaths,
    bool addAll = false,
    String projectName = _defaultProjectName,
  }) {
    return _post(
      '/vibe/git/change/commit',
      body: {
        'project_name': projectName,
        'message': message,
        'file_paths': filePaths,
        'add_all': addAll,
      },
    );
  }

  Future<List<GitCommit>> getResetCandidates({
    int limit = 20,
    String projectName = _defaultProjectName,
  }) async {
    final mock = await _settings.getGitMockMode();
    if (mock) {
      _log('GET /vibe/git/change/reset/candidates -> mock mode enabled');
      return [
        GitCommit(
          hash: 'a1b2c3d4',
          message: 'Add chat history persistence',
          date: DateTime.now().subtract(const Duration(hours: 2)),
          author: 'Dev',
        ),
        GitCommit(
          hash: 'b2c3d4e5',
          message: 'Implement voice input mode',
          date: DateTime.now().subtract(const Duration(hours: 5)),
          author: 'Dev',
        ),
      ];
    }

    final response = await _get(
      '/vibe/git/change/reset/candidates',
      query: {
        'project_name': projectName,
        'limit': '$limit',
      },
    );
    if (!response.success) throw Exception(response.message);
    return _parseCommitList(response.details);
  }

  Future<GitOperationResult> reset({
    required String hash,
    required String mode,
    String projectName = _defaultProjectName,
  }) {
    return _post(
      '/vibe/git/change/reset',
      body: {
        'project_name': projectName,
        'commit_hash': hash,
        'mode': mode,
      },
    );
  }

  Future<GitOperationResult> stash({
    String message = 'wip',
    bool includeUntracked = true,
    String projectName = _defaultProjectName,
  }) {
    return _post(
      '/vibe/git/advanced/stash',
      body: {
        'project_name': projectName,
        'message': message,
        'include_untracked': includeUntracked,
      },
    );
  }

  Future<GitOperationResult> stashPop({
    String? stashRef,
    String projectName = _defaultProjectName,
  }) {
    return _post(
      '/vibe/git/advanced/stash/pop',
      body: {
        'project_name': projectName,
        if (stashRef != null && stashRef.isNotEmpty) 'stash_ref': stashRef,
      },
    );
  }

  Future<List<String>> getBranches({
    String projectName = _defaultProjectName,
  }) async {
    final mock = await _settings.getGitMockMode();
    if (mock) {
      _log('GET /vibe/git/advanced/branches -> mock mode enabled');
      return ['main', 'develop', 'feature/voice-input', 'release/v1.0'];
    }

    final response = await _get(
      '/vibe/git/advanced/branches',
      query: {'project_name': projectName},
    );
    if (!response.success) throw Exception(response.message);
    final payload = _payload(response.details);
    if (payload is List) {
      return payload.map((item) => item.toString()).toList();
    }
    if (payload is Map<String, dynamic>) {
      final items = _readList(payload, ['branches', 'items']);
      return items.map((item) => item.toString()).toList();
    }
    return <String>[];
  }

  Future<GitOperationResult> checkout({
    required String branch,
    String projectName = _defaultProjectName,
  }) {
    return _post(
      '/vibe/git/advanced/checkout',
      body: {
        'project_name': projectName,
        'branch': branch,
      },
    );
  }

  Future<List<GitCommit>> log({
    int limit = 20,
    String projectName = _defaultProjectName,
  }) async {
    final mock = await _settings.getGitMockMode();
    if (mock) {
      _log('GET /vibe/git/advanced/log -> mock mode enabled');
      return [
        GitCommit(
          hash: '8a1f3c2',
          message: 'Improve chat rendering',
          date: DateTime.now().subtract(const Duration(days: 1)),
          author: 'Dev',
        ),
        GitCommit(
          hash: 'c4d9b21',
          message: 'Wire up git drawer UI',
          date: DateTime.now().subtract(const Duration(days: 2)),
          author: 'Dev',
        ),
        GitCommit(
          hash: '5f77ab0',
          message: 'Add auth gate',
          date: DateTime.now().subtract(const Duration(days: 4)),
          author: 'Dev',
        ),
      ];
    }

    final response = await _get(
      '/vibe/git/advanced/log',
      query: {
        'project_name': projectName,
        'limit': '$limit',
      },
    );
    if (!response.success) throw Exception(response.message);
    return _parseCommitList(response.details);
  }

  Future<GitWorktreeStatus> status({
    String projectName = _defaultProjectName,
  }) async {
    final mock = await _settings.getGitMockMode();
    if (mock) {
      _log('GET /vibe/git/worktree/status -> mock mode enabled');
      return GitWorktreeStatus(
        files: [
          GitWorktreeFile(path: 'lib/screens/chat_screen.dart', statusCode: 'M'),
          GitWorktreeFile(path: 'lib/widgets/input_bar.dart', statusCode: 'M'),
          GitWorktreeFile(path: 'lib/models/message.dart', statusCode: 'A'),
          GitWorktreeFile(path: 'assets/logo.png', statusCode: 'D'),
        ],
        counts: const {'M': 2, 'A': 1, 'D': 1},
      );
    }

    final response = await _get(
      '/vibe/git/worktree/status',
      query: {'project_name': projectName},
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
    final mock = await _settings.getGitMockMode();
    if (mock) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final opName = path.split('/').where((e) => e.isNotEmpty).last;
      _log('POST $path -> mock mode enabled, body=${jsonEncode(body)}');
      return GitOperationResult(success: true, message: 'Mock $opName complete.');
    }
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
    final token = await _settings.getGitToken();
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
    final requestBody = <String, dynamic>{
      ...?body,
      if (repoPath != null && repoPath.isNotEmpty) 'repo_path': repoPath,
    };

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
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        );
      } else {
        response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(requestBody),
        );
      }

      final payload = _safeDecode(response.body);
      final message = _extractMessage(payload) ??
          (response.statusCode >= 200 && response.statusCode < 300
              ? 'Operation succeeded'
              : 'Git operation failed.');

      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      _log(
        '$method $path done status=${response.statusCode} '
        'success=${response.statusCode >= 200 && response.statusCode < 300} '
        'elapsed=${elapsedMs}ms body=${_truncate(response.body)}',
      );

      return GitOperationResult(
        success: response.statusCode >= 200 && response.statusCode < 300,
        message: message,
        details: response.body,
      );
    } catch (error) {
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      _log('$method $path exception after ${elapsedMs}ms: $error');
      return GitOperationResult(success: false, message: 'Network error.', details: error.toString());
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
    final hash = _readString(item, ['hash', 'commit_hash', 'id'], fallback: 'unknown');
    final message = _readString(item, ['message', 'subject'], fallback: '');
    final dateStr = _nullableString(item['date']) ??
        _nullableString(item['timestamp']) ??
        _nullableString(item['committed_at']);
    return GitCommit(
      hash: hash,
      message: message,
      date: _parseDate(dateStr),
      author: _nullableString(item['author']) ?? _nullableString(item['author_name']),
    );
  }

  List<GitWorktreeFile> _parseWorktreeFiles(List<dynamic> raw) {
    return raw.whereType<Map<String, dynamic>>().map((item) {
      final path = _readString(item, ['path', 'file_path'], fallback: '');
      final statusCode = _readString(item, ['status', 'status_code'], fallback: 'M');
      return GitWorktreeFile(path: path, statusCode: statusCode);
    }).where((item) => item.path.isNotEmpty).toList();
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
      for (final key in const ['message', 'msg', 'detail']) {
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

  String _readString(Map<String, dynamic> map, List<String> keys, {required String fallback}) {
    for (final key in keys) {
      final value = _nullableString(map[key]);
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }

  int _readInt(Map<String, dynamic> map, List<String> keys, {required int fallback}) {
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

  String _truncate(String value, {int max = 500}) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}...';
  }
}
