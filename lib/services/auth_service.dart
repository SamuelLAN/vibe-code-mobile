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

  void _syncAuthStateFromTokenManager() {
    final nextAuthenticated = _tokenManager.hasValidToken;
    if (_isAuthenticated == nextAuthenticated) return;

    _isAuthenticated = nextAuthenticated;
    notifyListeners();
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;

    _tokenManager = TokenManager(
      apiClient: _apiClient,
      store: _store,
    );
    await _tokenManager.initialize();
    _tokenManager.addListener(_syncAuthStateFromTokenManager);

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
        _error = 'Invalid email or password';
      } else if (e.isForbidden) {
        _error = 'Account has been disabled';
      } else if (e.isTooManyRequests) {
        _error = 'Too many login attempts. Please try again later.';
      } else {
        _error = e.message;
      }

      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      debugPrint('Login exception: $e');

      // 检测网络连接错误
      final errorStr = e.toString();
      if (errorStr.contains('SocketException') ||
          errorStr.contains('Connection failed') ||
          errorStr.contains('No route to host') ||
          errorStr.contains('HandshakeException') ||
          errorStr.contains('TimeoutException')) {
        _error =
            'Network connection failed. Please check your network or server settings.';
      } else {
        _error = 'Network error: $e';
      }

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

  Future<bool> forceRefreshToken() async {
    if (!_isInitialized) {
      await _initialize();
    }
    return _tokenManager.forceRefresh();
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _tokenManager.removeListener(_syncAuthStateFromTokenManager);
      _tokenManager.dispose();
    }
    _apiClient.dispose();
    super.dispose();
  }
}
