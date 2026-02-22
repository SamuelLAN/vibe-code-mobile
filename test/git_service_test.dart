import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_code_mobile/services/git_service.dart';
import 'package:vibe_code_mobile/services/settings_service.dart';

import 'support/in_memory_store.dart';

void main() {
  test('git service returns mock operations when enabled', () async {
    final store = InMemoryStore();
    final settings = SettingsService(store: store);
    await settings.setGitMockMode(true);

    final git = GitService(settings: settings);
    final result = await git.pull();

    expect(result.success, isTrue);
    expect(result.message, contains('Mock'));
  });
}
