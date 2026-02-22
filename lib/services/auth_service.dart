import 'package:flutter/foundation.dart';

import 'key_value_store.dart';
import 'secure_store.dart';

class AuthService extends ChangeNotifier {
  AuthService({KeyValueStore? store}) : _store = store ?? const SecureStore();

  static const _tokenKey = 'session_token';

  static const String demoUsername = 'board';
  static const String demoPassword = 'cookie';

  final KeyValueStore _store;
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _error;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> tryAutoLogin() async {
    final token = await _store.read(_tokenKey);
    _isAuthenticated = token != null && token.isNotEmpty;
    notifyListeners();
  }

  Future<bool> login({required String username, required String password}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 900));

    if (username.trim() == demoUsername && password == demoPassword) {
      await _store.write(_tokenKey, 'session_${DateTime.now().millisecondsSinceEpoch}');
      _isAuthenticated = true;
      _isLoading = false;
      notifyListeners();
      return true;
    }

    _error = 'Invalid username or password.';
    _isLoading = false;
    _isAuthenticated = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    await _store.delete(_tokenKey);
    _isAuthenticated = false;
    notifyListeners();
  }
}
