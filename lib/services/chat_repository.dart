import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../apis/auth/auth_api.dart';
import '../config/api_config.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'auth_service.dart';
import 'settings_service.dart';

class ChatRepository {
  ChatRepository({
    AuthService? authService,
    SettingsService? settings,
    http.Client? client,
    String projectName = 'vibe-code-mobile',
  })  : _authService = authService,
        _settings = settings,
        _client = client ?? http.Client(),
        _defaultProjectName = projectName;

  final AuthService? _authService;
  final SettingsService? _settings;
  final http.Client _client;
  final String _defaultProjectName;

  final Map<String, Chat> _chatCache = {};
  final Map<String, String> _serverTitleCache = {};
  final Map<String, String?> _lastPreviewCache = {};
  final Map<String, List<Message>> _messages = {};

  Future<void> init() async {
    // 同步初始化，无需异步操作
  }

  Future<List<Chat>> getChats() async {
    final accessToken = await _authService?.getValidToken();
    if (accessToken == null) {
      return _sortedCachedChats();
    }

    try {
      final projectName = await _effectiveProjectName();
      final uri = Uri.parse('${ApiConfig.codeBaseUrl}/vibe/coding/chat/list')
          .replace(queryParameters: {
        'project_name': projectName,
        'limit': '50',
      });

      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode != 200) {
        throw ApiException.fromResponse(response);
      }

      final decoded = jsonDecode(response.body);
      final items = _extractList(decoded);
      final chats = items.map(_chatFromApi).toList();

      for (final chat in chats) {
        final cached = _chatCache[chat.id];
        final localPreview = _lastPreviewCache[chat.id];
        if (localPreview != null) {
          chat.lastMessagePreview = localPreview;
        } else if (cached?.lastMessagePreview != null) {
          chat.lastMessagePreview = cached!.lastMessagePreview;
        }
        if (cached != null && cached.updatedAt.isAfter(chat.updatedAt)) {
          chat.updatedAt = cached.updatedAt;
        }
        _chatCache[chat.id] = chat;
        _serverTitleCache[chat.id] = chat.title;
      }

      // Remove stale server snapshots but keep local-only chats (e.g. fallback-created).
      final serverIds = chats.map((c) => c.id).toSet();
      for (final id in _serverTitleCache.keys.toList()) {
        if (!serverIds.contains(id)) {
          _serverTitleCache.remove(id);
        }
      }

      return List.from(chats)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('[ChatRepository] getChats failed, fallback to cache: $e');
      return _sortedCachedChats();
    }
  }

  Future<Chat> createChat(Chat chat) async {
    final accessToken = await _authService?.getValidToken();
    if (accessToken == null) {
      _chatCache[chat.id] = chat;
      _messages[chat.id] = [];
      return chat;
    }

    try {
      final projectName = await _effectiveProjectName();
      final uri = Uri.parse('${ApiConfig.codeBaseUrl}/vibe/coding/chat/create');
      final response = await _client.post(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'project_name': projectName,
          'chat_title': chat.title,
        }),
      );
      if (response.statusCode != 200) {
        throw ApiException.fromResponse(response);
      }

      final decoded = jsonDecode(response.body);
      final chatData = _extractObject(decoded) ?? <String, dynamic>{};
      final created = _chatFromApi(chatData, fallbackTitle: chat.title);
      _chatCache[created.id] = created;
      _serverTitleCache[created.id] = created.title;
      _lastPreviewCache[created.id] = chat.lastMessagePreview;
      _messages.putIfAbsent(created.id, () => []);
      return created;
    } catch (e) {
      debugPrint('[ChatRepository] createChat failed, fallback local: $e');
      _chatCache[chat.id] = chat;
      _messages[chat.id] = [];
      return chat;
    }
  }

  Future<void> updateChat(Chat chat) async {
    _chatCache[chat.id] = chat;
    _lastPreviewCache[chat.id] = chat.lastMessagePreview;

    final accessToken = await _authService?.getValidToken();
    if (accessToken == null) return;

    final lastServerTitle = _serverTitleCache[chat.id];
    if (lastServerTitle == null || lastServerTitle == chat.title) {
      return;
    }

    try {
      final body = jsonEncode({
        'chat_id': chat.id,
        'chat_title': chat.title,
      });
      try {
        await _postRenameLike(
          accessToken: accessToken,
          path: '/vibe/coding/chat/title/edit',
          body: body,
        );
      } on ApiException catch (e) {
        debugPrint(
            '[ChatRepository] title/edit failed (${e.statusCode}), fallback to /chat/rename');
        await _postRenameLike(
          accessToken: accessToken,
          path: '/vibe/coding/chat/rename',
          body: body,
        );
      }
      _serverTitleCache[chat.id] = chat.title;
    } catch (e) {
      debugPrint('[ChatRepository] renameChat failed for ${chat.id}: $e');
    }
  }

  Future<void> deleteChat(String chatId) async {
    _chatCache.remove(chatId);
    _serverTitleCache.remove(chatId);
    _lastPreviewCache.remove(chatId);
    _messages.remove(chatId);

    final accessToken = await _authService?.getValidToken();
    if (accessToken == null) return;

    try {
      final uri = Uri.parse('${ApiConfig.codeBaseUrl}/vibe/coding/chat/delete');
      final response = await _client.post(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'chat_id': chatId}),
      );
      if (response.statusCode != 200) {
        throw ApiException.fromResponse(response);
      }
    } catch (e) {
      debugPrint('[ChatRepository] deleteChat failed for $chatId: $e');
    }
  }

  Future<Chat?> getChatDetail(String chatId) async {
    final accessToken = await _authService?.getValidToken();
    if (accessToken == null) {
      return _chatCache[chatId];
    }

    try {
      final uri = Uri.parse('${ApiConfig.codeBaseUrl}/vibe/coding/chat/detail')
          .replace(queryParameters: {'chat_id': chatId});
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode != 200) {
        throw ApiException.fromResponse(response);
      }

      final decoded = jsonDecode(response.body);
      final data = _extractObject(decoded);
      if (data == null) return _chatCache[chatId];
      final chat = _chatFromApi(data, fallbackTitle: _chatCache[chatId]?.title);
      final localPreview = _lastPreviewCache[chat.id];
      if (localPreview != null) {
        chat.lastMessagePreview = localPreview;
      }
      _chatCache[chat.id] = chat;
      _serverTitleCache[chat.id] = chat.title;
      return chat;
    } catch (e) {
      debugPrint('[ChatRepository] getChatDetail failed for $chatId: $e');
      return _chatCache[chatId];
    }
  }

  Future<List<Message>> getMessages(String chatId) async {
    return List.from(_messages[chatId] ?? []);
  }

  Future<void> deleteMessage(String chatId, String messageId) async {
    final messages = _messages[chatId];
    if (messages == null) return;
    messages.removeWhere((m) => m.id == messageId);
  }

  Future<void> addMessage(Message message) async {
    _messages.putIfAbsent(message.chatId, () => []);
    _messages[message.chatId]!.add(message);
  }

  Future<void> replaceMessages(String chatId, List<Message> messages) async {
    _messages[chatId] = List<Message>.from(messages);
  }

  Future<void> updateMessage(Message message) async {
    final messages = _messages[message.chatId];
    if (messages == null) return;

    final index = messages.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      messages[index] = message;
    }
  }

  Future<Chat> ensureChatExists(Chat chat) async {
    final accessToken = await _authService?.getValidToken();
    if (accessToken == null) {
      _chatCache[chat.id] = chat;
      _messages.putIfAbsent(chat.id, () => []);
      return chat;
    }

    try {
      final detail = await getChatDetail(chat.id);
      if (detail != null) {
        final localPreview = _lastPreviewCache[chat.id];
        if (localPreview != null && localPreview.trim().isNotEmpty) {
          detail.lastMessagePreview = localPreview;
        }
        _chatCache[detail.id] = detail;
        _messages.putIfAbsent(detail.id, () => _messages[chat.id] ?? []);
        return detail;
      }
    } catch (_) {
      // Fallback to create chat below.
    }

    final draft = Chat(
      id: chat.id,
      title: chat.title.trim().isEmpty ? 'New Chat' : chat.title,
      createdAt: chat.createdAt,
      updatedAt: chat.updatedAt,
      lastMessagePreview: chat.lastMessagePreview,
    );
    final created = await createChat(draft);
    if (created.id != chat.id) {
      final oldMessages = _messages.remove(chat.id);
      if (oldMessages != null) {
        _messages.putIfAbsent(created.id, () => oldMessages);
      } else {
        _messages.putIfAbsent(created.id, () => []);
      }
      _chatCache.remove(chat.id);
      _serverTitleCache.remove(chat.id);
      final preview = _lastPreviewCache.remove(chat.id);
      if (preview != null) {
        _lastPreviewCache[created.id] = preview;
      }
    } else {
      _messages.putIfAbsent(created.id, () => []);
    }
    return created;
  }

  void dispose() {
    _client.close();
  }

  List<Chat> _sortedCachedChats() {
    return _chatCache.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  List<Map<String, dynamic>> _extractList(dynamic decoded) {
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (decoded is! Map) return const [];
    final map = Map<String, dynamic>.from(decoded);
    final data = map['data'];
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (data is Map<String, dynamic>) {
      final list =
          data['list'] ?? data['items'] ?? data['records'] ?? data['chats'];
      if (list is List) {
        return list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return const [];
  }

  Map<String, dynamic>? _extractObject(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map) {
        if (data['chat'] is Map) {
          return Map<String, dynamic>.from(data['chat'] as Map);
        }
        return Map<String, dynamic>.from(data);
      }
      if (data is List && data.isNotEmpty && data.first is Map) {
        return Map<String, dynamic>.from(data.first as Map);
      }
      return decoded;
    }
    return null;
  }

  Chat _chatFromApi(Map<String, dynamic> map, {String? fallbackTitle}) {
    final id =
        (map['chat_id'] ?? map['memory_id'] ?? map['id'] ?? '').toString();
    if (id.isEmpty) {
      throw const FormatException('chat_id missing in chat payload');
    }

    final title =
        (map['chat_title'] ?? map['title'] ?? fallbackTitle ?? 'New Chat')
            .toString();
    final createdAt = _parseDateTime(
      map['created_time'] ?? map['createdAt'] ?? map['created_at'],
    );
    final updatedAt = _parseDateTime(
      map['updated_time'] ?? map['updatedAt'] ?? map['updated_at'],
    );

    return Chat(
      id: id,
      title: title,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? createdAt ?? DateTime.now(),
      lastMessagePreview: map['last_message_preview']?.toString(),
    );
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) {
      final ms = value > 1000000000000 ? value : value * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (value is double) {
      final intValue = value.toInt();
      final ms = intValue > 1000000000000 ? intValue : intValue * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final asInt = int.tryParse(text);
    if (asInt != null) {
      final ms = asInt > 1000000000000 ? asInt : asInt * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return DateTime.tryParse(text);
  }

  Future<void> _postRenameLike({
    required String accessToken,
    required String path,
    required String body,
  }) async {
    final response = await _client.post(
      Uri.parse('${ApiConfig.codeBaseUrl}$path'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: body,
    );
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }
  }

  Future<String> _effectiveProjectName() async {
    final selected = await _settings?.getSelectedProjectName();
    if (selected != null && selected.trim().isNotEmpty) {
      return selected.trim();
    }
    return _defaultProjectName;
  }
}
