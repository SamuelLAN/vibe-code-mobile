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
      final response = await _client.send(request);
      debugPrint('[TranscribeApi] 收到响应, statusCode: ${response.statusCode}');
      if (response.statusCode != 200) {
        final errorResponse = await http.Response.fromStream(response);
        debugPrint('[TranscribeApi] 响应 body: ${errorResponse.body}');
        onEvent(TranscribeEvent(
          type: TranscribeEventType.error,
          error: 'HTTP ${errorResponse.statusCode}: ${errorResponse.body}',
        ));
        return;
      }

      String? currentEvent;
      final dataLines = <String>[];
      var receivedAnyText = false;
      var emittedComplete = false;

      void flushEvent() {
        if (currentEvent == null && dataLines.isEmpty) return;
        final eventName = (currentEvent ?? 'message').trim().toLowerCase();
        final rawData = dataLines.join('\n');
        final parsed = _parseTranscribeSseEvent(
          eventName: eventName,
          rawData: rawData,
        );

        currentEvent = null;
        dataLines.clear();

        if (parsed == null) return;

        final textLength = parsed.text?.length ?? 0;
        final rawPreview = rawData.length <= 160
            ? rawData
            : '${rawData.substring(0, 160)}...';
        debugPrint(
          '[TranscribeApi][SSE] event=$eventName complete=${parsed.isComplete} '
          'textLen=$textLength error=${parsed.error ?? "-"} raw=$rawPreview',
        );

        if (parsed.text != null && parsed.text!.isNotEmpty) {
          receivedAnyText = true;
          onEvent(TranscribeEvent(
            type: TranscribeEventType.data,
            data: parsed.text,
            logId: parsed.logId,
          ));
        }

        if (parsed.error != null) {
          onEvent(TranscribeEvent(
            type: TranscribeEventType.error,
            error: parsed.error,
            logId: parsed.logId,
          ));
          return;
        }

        if (parsed.isComplete) {
          emittedComplete = true;
          onEvent(TranscribeEvent(
            type: TranscribeEventType.complete,
            data: parsed.text,
            logId: parsed.logId,
          ));
        }
      }

      await response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        if (line.isEmpty) {
          flushEvent();
          return;
        }
        if (line.startsWith('event:')) {
          currentEvent = line.substring(6).trim();
          return;
        }
        if (line.startsWith('data:')) {
          var data = line.substring(5);
          if (data.startsWith(' ')) {
            data = data.substring(1);
          }
          dataLines.add(data);
        }
      });

      flushEvent();

      // 一些服务不会显式发送 complete 事件；若已经收到文本则在流结束时补发完成。
      if (!emittedComplete && receivedAnyText) {
        debugPrint(
          '[TranscribeApi][SSE] stream ended without explicit complete; emit synthetic complete',
        );
        onEvent(TranscribeEvent(type: TranscribeEventType.complete));
      }
    } catch (e) {
      debugPrint('[TranscribeApi] 转写请求失败: $e');
      onEvent(TranscribeEvent(
        type: TranscribeEventType.error,
        error: 'Request failed: $e',
      ));
    }
  }

  _ParsedTranscribeEvent? _parseTranscribeSseEvent({
    required String eventName,
    required String rawData,
  }) {
    if (rawData.isEmpty && eventName == 'message') {
      return null;
    }

    if (rawData == '[DONE]') {
      return const _ParsedTranscribeEvent(isComplete: true);
    }

    try {
      final decoded = jsonDecode(rawData);
      if (decoded is Map<String, dynamic>) {
        final code = decoded['code'];
        final logId = decoded['log_id']?.toString();
        final msg = decoded['msg']?.toString();
        final text = _extractText(decoded);
        final isSuccessCode = code == 0 || code == 200 || code == null;
        final done = decoded['done'] == true ||
            decoded['is_done'] == true ||
            decoded['completed'] == true ||
            (decoded['status']?.toString().toLowerCase() == 'completed') ||
            eventName == 'complete' ||
            eventName == 'done' ||
            eventName == 'finish' ||
            eventName == 'finished';

        if (!isSuccessCode) {
          return _ParsedTranscribeEvent(
            error: msg ?? 'Unknown error',
            logId: logId,
          );
        }

        return _ParsedTranscribeEvent(
          text: text,
          logId: logId,
          isComplete: done,
        );
      }

      if (decoded is String) {
        final isComplete = eventName == 'complete' || decoded == '[DONE]';
        return _ParsedTranscribeEvent(text: decoded, isComplete: isComplete);
      }
    } catch (_) {
      // 非 JSON 文本事件，按纯文本处理
    }

    final isComplete = eventName == 'complete' ||
        eventName == 'done' ||
        eventName == 'finish' ||
        rawData == '[DONE]';
    return _ParsedTranscribeEvent(
      text: rawData,
      isComplete: isComplete,
    );
  }

  String? _extractText(Map<String, dynamic> json) {
    final direct = json['data'] ?? json['text'] ?? json['content'] ?? json['result'];
    if (direct is String) return direct;
    if (direct is Map<String, dynamic>) {
      final nested = direct['text'] ??
          direct['content'] ??
          direct['transcript'] ??
          direct['result'];
      if (nested is String) return nested;
      if (nested is Map<String, dynamic>) {
        final nestedText =
            nested['text'] ?? nested['content'] ?? nested['transcript'];
        if (nestedText is String) return nestedText;
      }
    }
    return null;
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

class _ParsedTranscribeEvent {
  const _ParsedTranscribeEvent({
    this.text,
    this.error,
    this.logId,
    this.isComplete = false,
  });

  final String? text;
  final String? error;
  final String? logId;
  final bool isComplete;
}
