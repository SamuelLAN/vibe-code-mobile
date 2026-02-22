import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/git_models.dart';
import 'settings_service.dart';

class GitService extends ChangeNotifier {
  GitService({SettingsService? settings}) : _settings = settings ?? SettingsService();

  final SettingsService _settings;

  bool _busy = false;
  bool get isBusy => _busy;

  Future<GitOperationResult> pull() async {
    return _runOperation('pull', body: {});
  }

  Future<GitOperationResult> push() async {
    return _runOperation('push', body: {});
  }

  Future<GitPushSummary> getPushSummary() async {
    final mock = await _settings.getGitMockMode();
    if (mock) {
      return GitPushSummary(branch: 'main', aheadCount: 2);
    }
    final response = await _post('/git/push-summary', body: {});
    if (response.success) {
      final data = jsonDecode(response.details ?? '{}') as Map<String, dynamic>;
      return GitPushSummary(
        branch: data['branch'] as String? ?? 'main',
        aheadCount: data['aheadCount'] as int? ?? 0,
      );
    }
    throw Exception(response.message);
  }

  Future<GitOperationResult> commit({required String message, required List<String> files}) async {
    return _runOperation('commit', body: {'message': message, 'files': files});
  }

  Future<GitOperationResult> reset({required String hash, required String mode}) async {
    return _runOperation('reset', body: {'hash': hash, 'mode': mode});
  }

  Future<GitOperationResult> stash() async {
    return _runOperation('stash', body: {});
  }

  Future<GitOperationResult> stashPop() async {
    return _runOperation('stash-pop', body: {});
  }

  Future<GitOperationResult> checkout({required String branch}) async {
    return _runOperation('checkout', body: {'branch': branch});
  }

  Future<List<GitCommit>> log() async {
    final mock = await _settings.getGitMockMode();
    if (mock) {
      return [
        GitCommit(hash: '8a1f3c2', message: 'Improve chat rendering', date: DateTime.now().subtract(const Duration(days: 1))),
        GitCommit(hash: 'c4d9b21', message: 'Wire up git drawer UI', date: DateTime.now().subtract(const Duration(days: 2))),
        GitCommit(hash: '5f77ab0', message: 'Add auth gate', date: DateTime.now().subtract(const Duration(days: 4))),
      ];
    }

    final response = await _post('/git/log', body: {});
    if (response.success) {
      final data = jsonDecode(response.details ?? '[]') as List<dynamic>;
      return data
          .map((item) => GitCommit(
                hash: item['hash'] as String,
                message: item['message'] as String,
                date: DateTime.parse(item['date'] as String),
              ))
          .toList();
    }
    throw Exception(response.message);
  }

  Future<List<String>> status() async {
    final mock = await _settings.getGitMockMode();
    if (mock) {
      return ['lib/screens/chat_screen.dart', 'lib/services/git_service.dart'];
    }
    final response = await _post('/git/status', body: {});
    if (response.success) {
      final data = jsonDecode(response.details ?? '[]') as List<dynamic>;
      return data.map((item) => item.toString()).toList();
    }
    throw Exception(response.message);
  }

  Future<GitOperationResult> _runOperation(String path, {required Map<String, dynamic> body}) async {
    final mock = await _settings.getGitMockMode();
    if (mock) {
      await Future.delayed(const Duration(milliseconds: 600));
      return GitOperationResult(success: true, message: 'Mock $path complete.');
    }
    return _post('/git/$path', body: body);
  }

  Future<GitOperationResult> _post(String path, {required Map<String, dynamic> body}) async {
    final baseUrl = await _settings.getGitBaseUrl();
    final repoPath = await _settings.getGitRepoPath();
    final token = await _settings.getGitToken();

    if (baseUrl == null || baseUrl.isEmpty || repoPath == null || repoPath.isEmpty) {
      return GitOperationResult(
        success: false,
        message: 'Git backend not configured.',
        details: 'Set Git base URL and repository path in settings.',
      );
    }

    _busy = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({...body, 'repoPath': repoPath}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return GitOperationResult(success: true, message: 'Operation succeeded', details: response.body);
      }

      return GitOperationResult(
        success: false,
        message: 'Git operation failed.',
        details: response.body,
      );
    } catch (error) {
      return GitOperationResult(success: false, message: 'Network error.', details: error.toString());
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
