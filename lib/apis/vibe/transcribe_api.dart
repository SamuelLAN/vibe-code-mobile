import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.files.add(await http.MultipartFile.fromPath('audio_file', audioFile.path));
    
    if (logId != null) {
      request.fields['log_id'] = logId;
    }

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

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
  }

  void dispose() {
    _client.close();
  }
}
