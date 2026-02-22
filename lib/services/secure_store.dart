import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_value_store.dart';

class SecureStore implements KeyValueStore {
  const SecureStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
}
