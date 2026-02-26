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

  /// æµå¼è½¬åé³é¢
  ///
  /// [audioFile] - é³é¢æä»¶
  /// [accessToken] - è®¿é®ä»¤ç
  /// [logId] - å¯éçæ¥å¿ ID
  /// [onEvent] - äºä»¶çå¬åè°
  Future<void> transcribeStream({
    required File audioFile,
    required String accessToken,
    String? logId,
    required TranscribeStreamListener onEvent,
  }) async {
    final uri = Uri.parse('$_baseUrl/vibe/transcribe/stream');

    // æ£æ¥é³é¢æä»¶æ¯å¦å­å¨
    if (!await audioFile.exists()) {
      debugPrint('[TranscribeApi] é³é¢æä»¶ä¸å­å¨: ${audioFile.path}');
      onEvent(TranscribeEvent(
        type: TranscribeEventType.error,
        error: 'é³é¢æä»¶ä¸å­å¨',
      ));
      return;
    }

    final fileSize = await audioFile.length();
    final fileExt = audioFile.path.split('.').last.toLowerCase();
    final mimeType = _getMimeType(audioFile.path);

    debugPrint('[TranscribeApi] é³é¢æä»¶è¯¦æ:');
    debugPrint('[TranscribeApi]   - è·¯å¾: ${audioFile.path}');
    debugPrint('[TranscribeApi]   - å¤§å°: $fileSize bytes');
    debugPrint('[TranscribeApi]   - æ©å±å: $fileExt');
    debugPrint('[TranscribeApi]   - MIMEç±»å: $mimeType');

    // éªè¯æä»¶å¤´
    try {
      final bytes = await audioFile.openRead(0, 4).first;
      final header = String.fromCharCodes(bytes);
      debugPrint('[TranscribeApi] æä»¶å¤´: $header (ææ: RIFF for WAV)');
      if (header != 'RIFF') {
        debugPrint('[TranscribeApi] è­¦å: æä»¶å¤´ä¸æ¯ RIFF, å®éæ¯ $header');
      }
    } catch (e) {
      debugPrint('[TranscribeApi] æ æ³è¯»åæä»¶å¤´: $e');
    }

    if (fileSize == 0) {
      debugPrint('[TranscribeApi] è­¦å: é³é¢æä»¶ä¸ºç©º!');
    }

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.files.add(await http.MultipartFile.fromPath('audio_file', audioFile.path));

    if (logId != null) {
      request.fields['log_id'] = logId;
      debugPrint('[TranscribeApi] log_id: $logId');
    }

    debugPrint('[TranscribeApi] å¼å§åéè½¬åè¯·æ±...');

    try {
      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('[TranscribeApi] æ¶å°ååº, statusCode: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('[TranscribeApi] ååº body: ${response.body}');
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

          // å¼å®¹ code: 0 å code: 200 ä¸¤ç§æåååº
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
