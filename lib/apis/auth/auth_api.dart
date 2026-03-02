import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';

/// 登录请求体
class LoginRequest {
  final String email;
  final String password;
  final String? deviceId;

  LoginRequest({
    required this.email,
    required this.password,
    this.deviceId,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'email': email,
      'password': password,
    };
    if (deviceId != null) map['device_id'] = deviceId;
    return map;
  }
}

/// 登录响应
class LoginResponse {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;

  LoginResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return LoginResponse(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      tokenType: data['token_type'] as String,
      expiresIn: data['expires_in'] as int,
    );
  }
}

/// Google OAuth 授权请求体
class GoogleAuthorizeRequest {
  final String state;

  GoogleAuthorizeRequest({required this.state});

  Map<String, dynamic> toJson() => {'state': state};
}

/// Google OAuth 授权响应
class GoogleAuthorizeResponse {
  final String authorizationEndpoint;
  final String clientId;
  final String responseType;
  final String scope;
  final String state;

  GoogleAuthorizeResponse({
    required this.authorizationEndpoint,
    required this.clientId,
    required this.responseType,
    required this.scope,
    required this.state,
  });

  factory GoogleAuthorizeResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return GoogleAuthorizeResponse(
      authorizationEndpoint: data['authorization_endpoint'] as String,
      clientId: data['client_id'] as String,
      responseType: data['response_type'] as String,
      scope: data['scope'] as String,
      state: data['state'] as String,
    );
  }
}

/// Google OAuth 回调请求体
class GoogleCallbackRequest {
  final String code;
  final String codeVerifier;
  final String redirectUrl;
  final String state;
  final String? deviceId;

  GoogleCallbackRequest({
    required this.code,
    required this.codeVerifier,
    required this.redirectUrl,
    required this.state,
    this.deviceId,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'code': code,
      'code_verifier': codeVerifier,
      'redirect_url': redirectUrl,
      'state': state,
    };
    if (deviceId != null) map['device_id'] = deviceId;
    return map;
  }
}

/// Token 刷新请求体
class RefreshTokenRequest {
  final String refreshToken;

  RefreshTokenRequest({required this.refreshToken});

  Map<String, dynamic> toJson() => {'refresh_token': refreshToken};
}

/// Token 刷新响应
class RefreshTokenResponse {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;

  RefreshTokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
  });

  factory RefreshTokenResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return RefreshTokenResponse(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      tokenType: data['token_type'] as String,
      expiresIn: data['expires_in'] as int,
    );
  }
}

/// Token 验证响应
class VerifyTokenResponse {
  final bool active;
  final Map<String, dynamic> claims;

  VerifyTokenResponse({
    required this.active,
    required this.claims,
  });

  factory VerifyTokenResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return VerifyTokenResponse(
      active: data['active'] as bool,
      claims: data['claims'] as Map<String, dynamic>,
    );
  }
}

/// API 错误异常
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final int? code;

  ApiException({
    required this.statusCode,
    required this.message,
    this.code,
  });

  factory ApiException.fromResponse(http.Response response) {
    String message = 'Unknown error';
    int? code;

    debugPrint('API Error Response: ${response.statusCode} - ${response.body}');

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      message = body['msg'] as String? ?? message;
      code = body['code'] as int?;
    } catch (_) {
      message = response.reasonPhrase ?? message;
    }

    return ApiException(
      statusCode: response.statusCode,
      message: message,
      code: code,
    );
  }

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isTooManyRequests => statusCode == 429;

  @override
  String toString() => 'ApiException: [$statusCode] $message';
}

/// Auth API 客户端
class AuthApiClient {
  AuthApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String get _baseUrl => ApiConfig.authBaseUrl;

  Future<LoginResponse> login(LoginRequest request) async {
    final url = '$_baseUrl/auth/login';
    debugPrint('Login request to: $url');
    debugPrint('Login request body: ${request.toJson()}');

    final response = await _client.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );

    debugPrint('Login response status: ${response.statusCode}');
    debugPrint('Login response body: ${response.body}');

    if (response.statusCode == 200) {
      return LoginResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw ApiException.fromResponse(response);
  }

  Future<void> logout(String token, {bool logoutAllDevices = false}) async {
    final queryParams = {'token': token};
    if (logoutAllDevices) {
      queryParams['logout_all_devices'] = 'true';
    }

    final uri = Uri.parse('$_baseUrl/auth/logout').replace(
      queryParameters: queryParams,
    );

    final response = await _client.post(uri);

    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  Future<GoogleAuthorizeResponse> googleAuthorize(
      GoogleAuthorizeRequest request) async {
    final url = '$_baseUrl/auth/google/authorize';

    final response = await _client.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );

    if (response.statusCode == 200) {
      return GoogleAuthorizeResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw ApiException.fromResponse(response);
  }

  Future<LoginResponse> googleCallback(GoogleCallbackRequest request) async {
    final url = '$_baseUrl/auth/google/callback';

    final response = await _client.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );

    if (response.statusCode == 200) {
      return LoginResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw ApiException.fromResponse(response);
  }

  Future<RefreshTokenResponse> refreshToken(RefreshTokenRequest request) async {
    final uri = Uri.parse('$_baseUrl/auth/token/refresh').replace(
      queryParameters: {'refresh_token': request.refreshToken},
    );

    debugPrint('Refresh token request to: $uri');

    final response = await _client.post(uri);

    debugPrint('Refresh token response status: ${response.statusCode}');
    debugPrint('Refresh token response body: ${response.body}');

    if (response.statusCode == 200) {
      return RefreshTokenResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw ApiException.fromResponse(response);
  }

  Future<VerifyTokenResponse> verifyToken(String token) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/auth/token/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token}),
    );

    if (response.statusCode == 200) {
      return VerifyTokenResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw ApiException.fromResponse(response);
  }

  void dispose() {
    _client.close();
  }
}
