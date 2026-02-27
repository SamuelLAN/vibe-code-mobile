/// API 主机配置
class ApiConfig {
  ApiConfig._();

  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  /// 认证服务主机地址
  /// 优先读取 AUTH_BASE_URL；默认值保持当前本地开发地址。
  static String authHost = const String.fromEnvironment(
    'AUTH_BASE_URL',
    defaultValue: String.fromEnvironment(
      'AUTH_HOST',
      defaultValue: 'http://192.168.1.52:8002',
    ),
  );

  /// 代码服务主机地址
  /// 优先读取 CODE_BASE_URL；默认值保持当前本地开发地址。
  static String codeHost = const String.fromEnvironment(
    'CODE_BASE_URL',
    defaultValue: 'http://192.168.1.52:8007',
  );

  /// 兼容历史变量（若设置则覆盖 codeHost）。
  static String legacyCodeHost = const String.fromEnvironment(
    'P_CODE_HOST',
    defaultValue: String.fromEnvironment(
      'CODE_HOST',
      defaultValue: '',
    ),
  );

  /// 获取完整的认证 API 基础 URL
  static String get authBaseUrl => authHost;

  /// 获取完整的代码 API 基础 URL
  static String get codeBaseUrl {
    if (legacyCodeHost.trim().isNotEmpty) {
      return legacyCodeHost.trim();
    }
    return codeHost;
  }

  /// 更新配置（用于动态配置）
  static void update({
    String? authHost,
    String? codeHost,
  }) {
    if (authHost != null) ApiConfig.authHost = authHost;
    if (codeHost != null) ApiConfig.codeHost = codeHost;
  }
}
