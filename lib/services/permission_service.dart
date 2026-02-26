import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// 权限服务 - 统一管理应用权限
class PermissionService {
  PermissionService();

  /// 检查并请求麦克风权限
  /// 返回 true 表示已获得权限
  Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.status;
    debugPrint('麦克风权限状态: $status');

    if (status.isGranted) {
      return true;
    }

    // 权限被永久拒绝
    if (status.isPermanentlyDenied) {
      debugPrint('麦克风权限被永久拒绝，需要手动开启');
      return false;
    }

    // 请求权限
    final result = await Permission.microphone.request();
    debugPrint('麦克风权限请求结果: $result');
    return result.isGranted;
  }

  /// 检查麦克风权限状态
  Future<bool> hasMicrophonePermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// 检查麦克风权限是否被永久拒绝
  Future<bool> isMicrophonePermissionPermanentlyDenied() async {
    final status = await Permission.microphone.status;
    return status.isPermanentlyDenied;
  }

  /// 打开应用设置页面
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// 检查网络连接状态（iOS 不需要网络权限，但可以检查连接）
  /// 返回 true 表示有网络连接
  Future<bool> hasNetworkConnection() async {
    // iOS 上网络权限是默认授予的
    // 这里我们返回一个乐观的结果，实际网络连接由 HTTP 请求处理
    return true;
  }
}
