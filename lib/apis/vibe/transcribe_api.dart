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
    final fileExt = audioFile.path.split('.').last.toLowerCase();
    final mimeType = _getMimeType(audioFile.path);

    debugPrint('[TranscribeApi] 音频文件详情:');
    debugPrint('[TranscribeApi]   - 路径: ${audioFile.path}');
    debugPrint('[TranscribeApi]   - 大小: $fileSize bytes');
    debugPrint('[TranscribeApi]   - 扩展名: $fileExt');
    debugPrint('[TranscribeApi]   - MIME类型: $mimeType');

    // 验证文件签名（WAV 检查 RIFF；M4A 通常在 offset 4 看到 ftyp）
    try {
      final bytes = await audioFile.openRead(0, 12).fold<List<int>>(<int>[], (acc, chunk) {
        if (acc.length >= 12) return acc;
        acc.addAll(chunk);
        return acc.length > 12 ? acc.sublist(0, 12) : acc;
      });
      final ascii = bytes.map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.').join();
      debugPrint('[TranscribeApi] 文件签名(ascii): $ascii');
      if (fileExt == 'wav' && bytes.length >= 4) {
        final header = String.fromCharCodes(bytes.take(4));
        debugPrint('[TranscribeApi] WAV 文件头: $header (期望 RIFF)');
        if (header != 'RIFF') {
          debugPrint('[TranscribeApi] 警告: WAV 文件头不是 RIFF');
        }
      } else if (fileExt == 'm4a' && bytes.length >= 8) {
        final brand = String.fromCharCodes(bytes.skip(4).take(4));
        debugPrint('[TranscribeApi] M4A 品牌字段(offset4): $brand (常见 ftyp)');
      }
    } catch (e) {
      debugPrint('[TranscribeApi] 无法读取文件头: $e');
    }

    if (fileSize == 0) {
      debugPrint('[TranscribeApi] 警告: 音频文件为空!');
    }

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.files.add(await http.MultipartFile.fromPath('audio_file', audioFile.path));

    if (logId != null) {
      request.fields['log_id'] = logId;
      debugPrint('[TranscribeApi] log_id: $logId');
    }

    debugPrint('[TranscribeApi] 开始发送转写请求...');

    try {
      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('[TranscribeApi] 收到响应, statusCode: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('[TranscribeApi] 响应 body: ${response.body}');
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

          // 兼容 code: 0 和 code: 200 两种成功响应
          if (code == 0 || code == 200) {
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

  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      case 'webm':
        return 'audio/webm';
      default:
        return 'audio/mpeg';
    }
  }
}
