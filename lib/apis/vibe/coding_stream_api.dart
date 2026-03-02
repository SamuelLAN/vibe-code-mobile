import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../auth/auth_api.dart';

enum CodingStreamEventType {
  message,
  completed,
  interrupted,
  error,
}

enum FlowStatus {
  done,
  userInteraction,
  interrupted,
  failed,
  running,
  unknown,
}

class ChatFlowIdsData {
  ChatFlowIdsData({
    required this.chatId,
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.newestFirst,
  });

  final String chatId;
  final List<String> items;
  final int total;
  final int limit;
  final int offset;
  final bool newestFirst;
}

class CodingStreamEvent {
  CodingStreamEvent({
    required this.type,
    this.text,
    this.flowId,
    this.error,
    this.rawData,
  });

  final CodingStreamEventType type;
  final String? text;
  final String? flowId;
  final String? error;
  final String? rawData;
}

typedef CodingStreamListener = void Function(CodingStreamEvent event);

class CodingStreamApiClient {
  CodingStreamApiClient({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  String get _baseUrl => ApiConfig.codeBaseUrl;

  Future<void> startStream({
    required String accessToken,
    required String msg,
    required String mode,
    List<Map<String, dynamic>>? content,
    List<Map<String, dynamic>>? msgBlocks,
    String? flowId,
    String? chatId,
    String? memoryId,
    String? projectName,
    String? funcFeedback,
    required CodingStreamListener onEvent,
  }) async {
    final uri = Uri.parse('$_baseUrl/vibe/coding/stream/start');
    final body = <String, dynamic>{
      'msg': msg,
      'mode': mode,
    };
    final effectiveBlocks = content ?? msgBlocks;
    if (effectiveBlocks != null && effectiveBlocks.isNotEmpty) {
      body['content'] = effectiveBlocks;
    }
    if (flowId != null && flowId.isNotEmpty) {
      body['flow_id'] = flowId;
    }
    if (chatId != null && chatId.isNotEmpty) {
      body['chat_id'] = chatId;
    }
    if (memoryId != null && memoryId.isNotEmpty) {
      body['memory_id'] = memoryId;
    }
    if (projectName != null && projectName.isNotEmpty) {
      body['project_name'] = projectName;
    }
    if (funcFeedback != null && funcFeedback.isNotEmpty) {
      body['func_feedback'] = funcFeedback;
    }

    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode(body);

    try {
      final response = await _sendSseRequest(request);
      await _consumeSseResponse(
        response: response,
        onEvent: onEvent,
      );
    } on ApiException catch (e) {
      onEvent(CodingStreamEvent(
        type: CodingStreamEventType.error,
        error: e.message,
      ));
    } catch (e) {
      debugPrint('[CodingStreamApi] startStream error: $e');
      onEvent(CodingStreamEvent(
        type: CodingStreamEventType.error,
        error: 'Request failed: $e',
      ));
    }
  }

  Future<void> stopStream({
    required String accessToken,
    required String flowId,
  }) async {
    final uri = Uri.parse('$_baseUrl/vibe/coding/stream/stop').replace(
      queryParameters: {'flow_id': flowId},
    );

    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  Future<ChatFlowIdsData?> getChatFlowIds({
    required String accessToken,
    required String chatId,
    int limit = 50,
    int offset = 0,
  }) async {
    final safeLimit = limit.clamp(1, 500);
    final safeOffset = offset < 0 ? 0 : offset;
    final uri = Uri.parse('$_baseUrl/vibe/coding/chat/flow_ids').replace(
      queryParameters: {
        'chat_id': chatId,
        'limit': '$safeLimit',
        'offset': '$safeOffset',
      },
    );
    final response = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    final dataRaw = map['data'];
    if (dataRaw is! Map) return null;
    final data = Map<String, dynamic>.from(dataRaw);
    final itemsRaw = data['items'] ??
        data['flow_ids'] ??
        data['flowIds'] ??
        data['list'] ??
        data['ids'];
    final items = itemsRaw is List
        ? itemsRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    return ChatFlowIdsData(
      chatId: (data['chat_id'] ?? chatId).toString(),
      items: items,
      total: _toInt(data['total']) ?? items.length,
      limit: _toInt(data['limit']) ?? safeLimit,
      offset: _toInt(data['offset']) ?? safeOffset,
      newestFirst: data['newest_first'] == true,
    );
  }

  Future<FlowStatus> getFlowStatus({
    required String accessToken,
    required String flowId,
  }) async {
    final uri = Uri.parse('$_baseUrl/vibe/coding/flow/status').replace(
      queryParameters: {'flow_id': flowId},
    );
    final response = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return FlowStatus.unknown;
    final map = Map<String, dynamic>.from(decoded);
    final dataRaw = map['data'];
    if (dataRaw is! Map) return FlowStatus.unknown;
    final statusText =
        (dataRaw['status'] ?? '').toString().trim().toLowerCase();
    return switch (statusText) {
      'done' => FlowStatus.done,
      'user_interaction' => FlowStatus.userInteraction,
      'interrupted' => FlowStatus.interrupted,
      'failed' => FlowStatus.failed,
      'running' => FlowStatus.running,
      _ => FlowStatus.unknown,
    };
  }

  Future<List<CodingStreamEvent>> getFlowData({
    required String accessToken,
    required String flowId,
  }) async {
    final uri = Uri.parse('$_baseUrl/vibe/coding/flow/data').replace(
      queryParameters: {'flow_id': flowId},
    );
    final request = http.Request('GET', uri)
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..headers['Accept'] = 'text/event-stream';

    final response = await _sendSseRequest(request);
    final events = <CodingStreamEvent>[];
    await _consumeSseResponse(
      response: response,
      onEvent: events.add,
    );
    return events;
  }

  void dispose() {
    _client.close();
  }

  Future<http.StreamedResponse> _sendSseRequest(http.Request request) async {
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      final errorResponse = await http.Response.fromStream(response);
      throw ApiException.fromResponse(errorResponse);
    }
    return response;
  }

  Future<void> _consumeSseResponse({
    required http.StreamedResponse response,
    required CodingStreamListener onEvent,
  }) async {
    String? currentEvent;
    final dataLines = <String>[];

    Future<void> flushEvent() async {
      if (currentEvent == null && dataLines.isEmpty) return;
      final eventName = (currentEvent ?? 'message').trim();
      final rawData = dataLines.join('\n');
      _emitParsedEvent(
        eventName: eventName,
        rawData: rawData,
        onEvent: onEvent,
      );
      currentEvent = null;
      dataLines.clear();
    }

    await response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) async {
      if (line.isEmpty) {
        await flushEvent();
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

    await flushEvent();
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  void _emitParsedEvent({
    required String eventName,
    required String rawData,
    required CodingStreamListener onEvent,
  }) {
    if (rawData.isEmpty && eventName == 'message') {
      return;
    }

    String? text;
    String? flowId;
    String? error;

    if (rawData.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawData);
        if (decoded is Map<String, dynamic>) {
          flowId = decoded['flow_id'] as String? ??
              (decoded['data'] is Map<String, dynamic>
                  ? (decoded['data'] as Map<String, dynamic>)['flow_id']
                      as String?
                  : null);

          final directText = decoded['message'] ??
              decoded['msg'] ??
              decoded['content'] ??
              decoded['text'];
          if (directText is String) {
            text = directText;
          }

          final data = decoded['data'];
          if (text == null && data is String) {
            text = data;
          } else if (text == null && data is Map<String, dynamic>) {
            final nestedText = data['message'] ??
                data['content'] ??
                data['text'] ??
                data['delta'];
            if (nestedText is String) {
              text = nestedText;
            }
            flowId ??= data['flow_id'] as String?;
          }

          final errText = decoded['error'] ?? decoded['msg'];
          if (errText is String) {
            error = errText;
          }
        } else if (decoded is String) {
          text = decoded;
        }
      } catch (_) {
        text = rawData;
      }
    }

    final type = switch (eventName) {
      'message' => CodingStreamEventType.message,
      'completed' => CodingStreamEventType.completed,
      'interrupted' => CodingStreamEventType.interrupted,
      'stopped' => CodingStreamEventType.interrupted,
      'timeout' => CodingStreamEventType.error,
      'error' => CodingStreamEventType.error,
      _ => CodingStreamEventType.message,
    };

    onEvent(CodingStreamEvent(
      type: type,
      text: text,
      flowId: flowId,
      error: error,
      rawData: rawData,
    ));
  }
}
