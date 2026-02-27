import 'package:flutter_test/flutter_test.dart';
import 'package:plutux_code/services/git_service.dart';
import 'package:plutux_code/services/settings_service.dart';

import 'support/in_memory_store.dart';

void main() {
  test('git service uses real mode and fails without auth token', () async {
    final store = InMemoryStore();
    final settings = SettingsService(store: store);

    final git = GitService(settings: settings);
    final result = await git.pull();

    expect(result.success, isFalse);
    expect(result.message, isNotEmpty);
  });
}
