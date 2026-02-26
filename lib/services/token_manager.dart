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

  // 使用单个键存储所有 token 信息（JSON 格式），减少 I/O 操作
  static const _tokenDataKey = 'token_data';

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
  /// 从存储中恢复 token 信息（单次 I/O）
  Future<void> initialize() async {
    // 一次性读取所有 token 数据
    final tokenDataJson = await _store.read(_tokenDataKey);

    if (tokenDataJson != null) {
      try {
        // 解析 JSON 数据
        final data = _parseTokenData(tokenDataJson);
        if (data != null) {
          _tokenInfo = TokenInfo(
            accessToken: data['accessToken']!,
            refreshToken: data['refreshToken']!,
            expiresAt: DateTime.parse(data['expiresAt']!),
            createdAt: DateTime.parse(data['createdAt']!),
          );
          _scheduleRefresh();
        }
      } catch (e) {
        // 数据解析失败，清除损坏的数据
        await _clearTokenInfo();
        debugPrint('Token data corrupted, cleared: $e');
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  Map<String, String>? _parseTokenData(String json) {
    // 简单解析 key=value&key=value 格式
    final result = <String, String>{};
    final pairs = json.split('&');
    for (final pair in pairs) {
      final idx = pair.indexOf('=');
      if (idx > 0) {
        final key = pair.substring(0, idx);
        final value = pair.substring(idx + 1);
        result[key] = Uri.decodeComponent(value);
      }
    }
    if (result.length >= 4) {
      return result;
    }
    return null;
  }

  String _encodeTokenData(TokenInfo info) {
    return 'accessToken=${Uri.encodeComponent(info.accessToken)}'
        '&refreshToken=${Uri.encodeComponent(info.refreshToken)}'
        '&expiresAt=${Uri.encodeComponent(info.expiresAt.toIso8601String())}'
        '&createdAt=${Uri.encodeComponent(info.createdAt.toIso8601String())}';
  }

  /// 保存 token 信息到存储（单次 I/O）
  Future<void> _saveTokenInfo(TokenInfo info) async {
    await _store.write(_tokenDataKey, _encodeTokenData(info));
  }

  /// 清除 token 信息
  Future<void> _clearTokenInfo() async {
    await _store.delete(_tokenDataKey);
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

    debugPrint('Attempting token refresh with refresh_token: ${_tokenInfo!.refreshToken}');

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
