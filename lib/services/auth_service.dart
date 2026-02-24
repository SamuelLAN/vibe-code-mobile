import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../apis/auth/auth_api.dart';
import 'key_value_store.dart';
import 'secure_store.dart';
import 'token_manager.dart';

class AuthService extends ChangeNotifier {
  AuthService({
    KeyValueStore? store,
    AuthApiClient? apiClient,
  })  : _store = store ?? const SecureStore(),
        _apiClient = apiClient ?? AuthApiClient();

  static const _deviceIdKey = 'device_id';

  final KeyValueStore _store;
  final AuthApiClient _apiClient;
  late final TokenManager _tokenManager;

  bool _isInitialized = false;
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _error;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get accessToken => _tokenManager.accessToken;

  Future<void> _initialize() async {
    if (_isInitialized) return;

    _tokenManager = TokenManager(
      apiClient: _apiClient,
      store: _store,
    );
    await _tokenManager.initialize();

    _isAuthenticated = _tokenManager.hasValidToken;
    _isInitialized = true;
  }

  Future<void> tryAutoLogin() async {
    await _initialize();
    _isAuthenticated = _tokenManager.hasValidToken;
    notifyListeners();
  }

  Future<String?> _getDeviceId() async {
    var deviceId = await _store.read(_deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await _store.write(_deviceIdKey, deviceId);
    }
    return deviceId;
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    await _initialize();

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final deviceId = await _getDeviceId();
      final response = await _apiClient.login(
        LoginRequest(
          email: email,
          password: password,
          deviceId: deviceId,
        ),
      );

      await _tokenManager.setTokens(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        expiresIn: response.expiresIn,
      );

      _isAuthenticated = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _isLoading = false;

      if (e.isUnauthorized) {
        _error = '邮箱或密码错误';
      } else if (e.isForbidden) {
        _error = '账户已被禁用';
      } else if (e.isTooManyRequests) {
        _error = '登录尝试过多，请稍后再试';
      } else {
        _error = e.message;
      }

      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _error = '网络错误，请检查网络连接';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout({bool logoutAllDevices = false}) async {
    final token = _tokenManager.accessToken;
    if (token != null) {
      try {
        await _apiClient.logout(token, logoutAllDevices: logoutAllDevices);
      } catch (e) {
        debugPrint('Logout API error: $e');
      }
    }

    await _tokenManager.clearTokens();
    _isAuthenticated = false;
    notifyListeners();
  }

  /// 确保 access token 有效（如果正在刷新会等待刷新完成）
  Future<String?> getValidToken() async {
    if (!_isInitialized) {
      await _initialize();
    }
    return _tokenManager.ensureValidToken();
  }

  @override
  void dispose() {
    _tokenManager.dispose();
    _apiClient.dispose();
    super.dispose();
  }
}
