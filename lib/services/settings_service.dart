import 'key_value_store.dart';
import 'secure_store.dart';
import '../config/api_config.dart';

class SettingsService {
  SettingsService({KeyValueStore? store}) : _store = store ?? const SecureStore();

  final KeyValueStore _store;

  static const _gitBaseUrlKey = 'git_base_url';
  static const _gitRepoPathKey = 'git_repo_path';
  static const _projectNameKey = 'selected_project_name';

  Future<String?> getGitBaseUrl() async {
    final value = await _store.read(_gitBaseUrlKey);
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
    return ApiConfig.codeBaseUrl;
  }
  Future<String?> getGitRepoPath() => _store.read(_gitRepoPathKey);
  Future<String?> getSelectedProjectName() => _store.read(_projectNameKey);
  // Git mock mode is permanently disabled. All git actions must use real APIs.
  Future<bool> getGitMockMode() async => false;

  Future<void> setGitBaseUrl(String value) => _store.write(_gitBaseUrlKey, value.trim());
  Future<void> setGitRepoPath(String value) => _store.write(_gitRepoPathKey, value.trim());
  Future<void> setSelectedProjectName(String value) =>
      _store.write(_projectNameKey, value.trim());
  Future<void> setGitMockMode(bool enabled) async {}
}
