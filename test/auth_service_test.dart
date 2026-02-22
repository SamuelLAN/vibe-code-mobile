import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_code_mobile/services/auth_service.dart';

import 'support/in_memory_store.dart';

void main() {
  test('auth service logs in with demo credentials', () async {
    final service = AuthService(store: InMemoryStore());
    final success = await service.login(username: AuthService.demoUsername, password: AuthService.demoPassword);
    expect(success, isTrue);
    expect(service.isAuthenticated, isTrue);
  });

  test('auth service rejects invalid credentials', () async {
    final service = AuthService(store: InMemoryStore());
    final success = await service.login(username: 'wrong', password: 'bad');
    expect(success, isFalse);
    expect(service.isAuthenticated, isFalse);
    expect(service.error, isNotNull);
  });
}
