import 'dart:async';

import 'package:flutter/foundation.dart';

import '../apis/auth/auth_api.dart';
import 'key_value_store.dart';
import 'secure_store.dart';

/// Token 类型
enum TokenType {
  access,
  refresh,
}

/// Token 信息
class TokenInfo {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final DateTime createdAt;

  TokenInfo({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.createdAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get needsRefresh {
    final bufferTime = const Duration(minutes: 5);
    return DateTime.now().add(bufferTime).isAfter(expiresAt);
  }

  Duration get timeUntilExpiry => expiresAt.difference(DateTime.now());
}

/// Token 管理器
/// 负责维护 access token 和 refresh token 的有效性
/// 使用后台 worker 定期检查并自动刷新
class TokenManager extends ChangeNotifier {
  TokenManager({
    required AuthApiClient apiClient,
    KeyValueStore? store,
  })  : _apiClient = apiClient,
        _store = store ?? const SecureStore();

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _tokenExpiresAtKey = 'token_expires_at';
  static const _tokenCreatedAtKey = 'token_created_at';

  final AuthApiClient _apiClient;
  final KeyValueStore _store;

  TokenInfo? _tokenInfo;
  bool _isRefreshing = false;
  Timer? _refreshTimer;
  bool _isInitialized = false;

  TokenInfo? get tokenInfo => _tokenInfo;
  bool get isInitialized => _isInitialized;
  bool get hasValidToken => _tokenInfo != null && !_tokenInfo!.isExpired;

  /// 获取当前的 access token
  String? get accessToken => _tokenInfo?.accessToken;

  /// 初始化 token 管理器
  /// 从存储中恢复 token 信息
  Future<void> initialize() async {
    final accessToken = await _store.read(_accessTokenKey);
    final refreshToken = await _store.read(_refreshTokenKey);
    final expiresAtStr = await _store.read(_tokenExpiresAtKey);
    final createdAtStr = await _store.read(_tokenCreatedAtKey);

    if (accessToken != null &&
        refreshToken != null &&
        expiresAtStr != null &&
        createdAtStr != null) {
      _tokenInfo = TokenInfo(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: DateTime.parse(expiresAtStr),
        createdAt: DateTime.parse(createdAtStr),
      );
      _scheduleRefresh();
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// 保存 token 信息到存储
  Future<void> _saveTokenInfo(TokenInfo info) async {
    await _store.write(_accessTokenKey, info.accessToken);
    await _store.write(_refreshTokenKey, info.refreshToken);
    await _store.write(_tokenExpiresAtKey, info.expiresAt.toIso8601String());
    await _store.write(_tokenCreatedAtKey, info.createdAt.toIso8601String());
  }

  /// 清除 token 信息
  Future<void> _clearTokenInfo() async {
    await _store.delete(_accessTokenKey);
    await _store.delete(_refreshTokenKey);
    await _store.delete(_tokenExpiresAtKey);
    await _store.delete(_tokenCreatedAtKey);
  }

  /// 设置新的 token 信息
  Future<void> setTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
  }) async {
    final now = DateTime.now();
    _tokenInfo = TokenInfo(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: now.add(Duration(seconds: expiresIn)),
      createdAt: now,
    );

    await _saveTokenInfo(_tokenInfo!);
    _scheduleRefresh();
    notifyListeners();
  }

  /// 清除 token（登出时调用）
  Future<void> clearTokens() async {
    _cancelRefreshTimer();
    _tokenInfo = null;
    await _clearTokenInfo();
    notifyListeners();
  }

  /// 安排自动刷新
  void _scheduleRefresh() {
    _cancelRefreshTimer();

    if (_tokenInfo == null) return;

    final timeUntilExpiry = _tokenInfo!.timeUntilExpiry;

    // 在 token 过期前 5 分钟开始刷新
    final refreshTime = timeUntilExpiry - const Duration(minutes: 5);

    if (refreshTime.isNegative) {
      // 立即刷新
      _doRefresh();
      return;
    }

    _refreshTimer = Timer(refreshTime, _doRefresh);
  }

  /// 取消刷新定时器
  void _cancelRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// 执行 token 刷新
  Future<void> _doRefresh() async {
    if (_isRefreshing || _tokenInfo == null) return;

    _isRefreshing = true;

    try {
      final response = await _apiClient.refreshToken(
        RefreshTokenRequest(refreshToken: _tokenInfo!.refreshToken),
      );

      await setTokens(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        expiresIn: response.expiresIn,
      );
    } catch (e) {
      // 刷新失败，清除 token
      debugPrint('Token refresh failed: $e');
      await clearTokens();
    } finally {
      _isRefreshing = false;
    }
  }

  /// 强制刷新 token
  /// 用于在 API 调用返回 401 时主动刷新
  Future<bool> forceRefresh() async {
    if (_tokenInfo == null) return false;
    await _doRefresh();
    return hasValidToken;
  }

  /// 确保 token 有效
  /// 如果 token 即将过期，先刷新
  Future<String?> ensureValidToken() async {
    if (_tokenInfo == null) return null;

    if (_tokenInfo!.needsRefresh && !_isRefreshing) {
      await _doRefresh();
    }

    return _tokenInfo?.accessToken;
  }

  @override
  void dispose() {
    _cancelRefreshTimer();
    super.dispose();
  }
}
