/// API 主机配置
class ApiConfig {
  ApiConfig._();

  /// 认证服务主机地址
  /// 真机调试时需要改为 Mac 的局域网 IP 地址，如 http://192.168.1.x:8002
  static String authHost = const String.fromEnvironment(
    'AUTH_HOST',
    defaultValue: 'http://192.168.1.52:8002',
  );

  /// 代码服务主机地址
  static String codeHost = const String.fromEnvironment(
    'P_CODE_HOST',
    defaultValue: String.fromEnvironment(
      'CODE_HOST',
      defaultValue: 'http://192.168.1.52:8007',
    ),
  );

  /// 获取完整的认证 API 基础 URL
  static String get authBaseUrl => authHost;

  /// 获取完整的代码 API 基础 URL
  static String get codeBaseUrl => codeHost;

  /// 更新配置（用于动态配置）
  static void update({
    String? authHost,
    String? codeHost,
  }) {
    if (authHost != null) ApiConfig.authHost = authHost;
    if (codeHost != null) ApiConfig.codeHost = codeHost;
  }
}
