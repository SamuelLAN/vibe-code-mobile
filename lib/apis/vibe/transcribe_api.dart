import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';

/// 转写事件类型
enum TranscribeEventType {
  data,
  complete,
  error,
}

/// 转写事件
class TranscribeEvent {
  final TranscribeEventType type;
  final String? data;
  final String? error;
  final String? logId;

  TranscribeEvent({
    required this.type,
    this.data,
    this.error,
    this.logId,
  });
}

/// 转写流监听器
typedef TranscribeStreamListener = void Function(TranscribeEvent event);

/// 语音转写 API 客户端
class TranscribeApiClient {
  TranscribeApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String get _baseUrl => ApiConfig.codeBaseUrl;

  /// 流式转写音频
  /// 
  /// [audioFile] - 音频文件
  /// [accessToken] - 访问令牌
  /// [logId] - 可选的日志 ID
  /// [onEvent] - 事件监听回调
  Future<void> transcribeStream({
    required File audioFile,
    required String accessToken,
    String? logId,
    required TranscribeStreamListener onEvent,
  }) async {
    final uri = Uri.parse('$_baseUrl/vibe/transcribe/stream');

    // 检查音频文件是否存在
    if (!await audioFile.exists()) {
      debugPrint('[TranscribeApi] 音频文件不存在: ${audioFile.path}');
      onEvent(TranscribeEvent(
        type: TranscribeEventType.error,
        error: '音频文件不存在',
      ));
      return;
    }

    final fileSize = await audioFile.length();
    debugPrint('[TranscribeApi] 音频文件大小: $fileSize bytes, 路径: ${audioFile.path}');

    if (fileSize == 0) {
      debugPrint('[TranscribeApi] 警告: 音频文件为空!');
    }

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.files.add(await http.MultipartFile.fromPath('audio_file', audioFile.path));
    
    if (logId != null) {
      request.fields['log_id'] = logId;
    }

    debugPrint('[TranscribeApi] 开始发送转写请求...');

    try {
      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('[TranscribeApi] 收到响应, statusCode: ${response.statusCode}');
      debugPrint('[TranscribeApi] 响应 body: ${response.body}');

      if (response.statusCode != 200) {
        onEvent(TranscribeEvent(
          type: TranscribeEventType.error,
          error: 'Server error: ${response.statusCode}',
        ));
        return;
      }

      // 解析 SSE 流
      final lines = const LineSplitter().convert(response.body);
      for (final line in lines) {
        if (line.isEmpty) continue;

        // SSE 格式: "event: xxx\ndata: yyy\n"
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;

        final data = trimmed.substring(5).trim();

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final code = json['code'] as int?;

          if (code == 200) {
            final text = json['data'] as String?;
            final eventLogId = json['log_id'] as String?;

            if (text != null && text.isNotEmpty) {
              onEvent(TranscribeEvent(
                type: TranscribeEventType.data,
                data: text,
                logId: eventLogId,
              ));
            }

            // 完成信号
            onEvent(TranscribeEvent(
              type: TranscribeEventType.complete,
              data: text,
              logId: eventLogId,
            ));
          } else {
            final msg = json['msg'] as String? ?? 'Unknown error';
            onEvent(TranscribeEvent(
              type: TranscribeEventType.error,
              error: msg,
            ));
          }
        } catch (e) {
          // 可能是纯文本响应
          onEvent(TranscribeEvent(
            type: TranscribeEventType.data,
            data: data,
          ));
        }
      }
    } catch (e) {
      debugPrint('[TranscribeApi] 转写请求失败: $e');
      onEvent(TranscribeEvent(
        type: TranscribeEventType.error,
        error: 'Request failed: $e',
      ));
    }
  }

  void dispose() {
    _client.close();
  }
}
