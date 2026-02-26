import 'key_value_store.dart';
import 'secure_store.dart';

class SettingsService {
  SettingsService({KeyValueStore? store}) : _store = store ?? const SecureStore();

  final KeyValueStore _store;

  static const _gitBaseUrlKey = 'git_base_url';
  static const _gitRepoPathKey = 'git_repo_path';
  static const _gitTokenKey = 'git_token';

  Future<String?> getGitBaseUrl() => _store.read(_gitBaseUrlKey);
  Future<String?> getGitRepoPath() => _store.read(_gitRepoPathKey);
  Future<String?> getGitToken() => _store.read(_gitTokenKey);
  // Git mock mode is permanently disabled. All git actions must use real APIs.
  Future<bool> getGitMockMode() async => false;

  Future<void> setGitBaseUrl(String value) => _store.write(_gitBaseUrlKey, value.trim());
  Future<void> setGitRepoPath(String value) => _store.write(_gitRepoPathKey, value.trim());
  Future<void> setGitToken(String value) => _store.write(_gitTokenKey, value.trim());
  Future<void> setGitMockMode(bool enabled) async {}
}
