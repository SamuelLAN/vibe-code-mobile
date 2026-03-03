import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
    String projectName = 'plutux-board',
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
  String? _activeChatId;
  Directory? _messageCacheDir;

  Future<void> init() async {
    await _ensureMessageCacheDir();
  }

  Future<List<Chat>> getChats({bool forceRefresh = false}) async {
    final localChats = await _readChatsFromDisk();
    _hydrateChatCache(localChats);

    if (!forceRefresh && localChats.isNotEmpty) {
      return _sortChats(localChats);
    }

    final accessToken = await _authService?.getValidToken();
    if (accessToken == null) {
      return _sortChats(localChats);
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

      final sorted = _sortChats(chats);
      await _writeChatsToDisk(sorted);
      _hydrateChatCache(sorted);
      return sorted;
    } catch (e) {
      debugPrint('[ChatRepository] getChats failed, fallback to local: $e');
      return _sortChats(localChats);
    }
  }

  Future<Chat> createChat(Chat chat) async {
    final accessToken = await _authService?.getValidToken();
    if (accessToken == null) {
      _chatCache[chat.id] = chat;
      _messages[chat.id] = [];
      await _upsertLocalChat(chat);
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
      await _upsertLocalChat(created);
      return created;
    } catch (e) {
      debugPrint('[ChatRepository] createChat failed, fallback local: $e');
      _chatCache[chat.id] = chat;
      _messages[chat.id] = [];
      await _upsertLocalChat(chat);
      return chat;
    }
  }

  Future<void> updateChat(Chat chat) async {
    _chatCache[chat.id] = chat;
    _lastPreviewCache[chat.id] = chat.lastMessagePreview;
    await _upsertLocalChat(chat);

    final accessToken = await _authService?.getValidToken();
    if (accessToken == null) return;

    final lastServerTitle = _serverTitleCache[chat.id];
    if (lastServerTitle == chat.title) {
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

  Future<String?> generateChatTitle(String userMsg) async {
    final trimmed = userMsg.trim();
    if (trimmed.isEmpty) return null;

    final accessToken = await _authService?.getValidToken();
    if (accessToken == null) return null;

    try {
      final uri =
          Uri.parse('${ApiConfig.codeBaseUrl}/vibe/coding/chat/title/generate');
      final response = await _client.post(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'user_msg': trimmed}),
      );
      if (response.statusCode != 200) {
        throw ApiException.fromResponse(response);
      }

      final decoded = jsonDecode(response.body);
      final title = _extractGeneratedTitle(decoded);
      if (title == null || title.trim().isEmpty) return null;
      return title.trim();
    } catch (e) {
      debugPrint('[ChatRepository] generateChatTitle failed: $e');
      return null;
    }
  }

  Future<void> deleteChat(String chatId) async {
    _chatCache.remove(chatId);
    _serverTitleCache.remove(chatId);
    _lastPreviewCache.remove(chatId);
    _messages.remove(chatId);
    if (_activeChatId == chatId) {
      _activeChatId = null;
    }
    await _deleteMessagesFromDisk(chatId);
    await _removeLocalChat(chatId);

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
    final local = await _getLocalChatById(chatId);
    final accessToken = await _authService?.getValidToken();
    if (accessToken == null) {
      return local ?? _chatCache[chatId];
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
      await _upsertLocalChat(chat);
      return chat;
    } catch (e) {
      debugPrint('[ChatRepository] getChatDetail failed for $chatId: $e');
      return local ?? _chatCache[chatId];
    }
  }

  Future<List<Message>> getMessages(String chatId) async {
    if (_activeChatId != chatId) {
      return await _loadMessagesForInactiveChat(chatId);
    }

    await _ensureMessagesLoaded(chatId);
    return List<Message>.from(_messages[chatId] ?? const <Message>[]);
  }

  Future<void> deleteMessage(String chatId, String messageId) async {
    await _ensureActiveForMutation(chatId);
    final messages = _messages[chatId];
    if (messages == null) return;
    messages.removeWhere((m) => m.id == messageId);
    await _persistMessages(chatId);
  }

  Future<void> addMessage(Message message) async {
    await _ensureActiveForMutation(message.chatId);
    _messages.putIfAbsent(message.chatId, () => []);
    _messages[message.chatId]!.add(message);
    await _persistMessages(message.chatId);
  }

  Future<void> replaceMessages(String chatId, List<Message> messages) async {
    await _ensureActiveForMutation(chatId);
    _messages[chatId] = List<Message>.from(messages);
    await _persistMessages(chatId);
  }

  Future<void> updateMessage(Message message) async {
    await _ensureActiveForMutation(message.chatId);
    final messages = _messages[message.chatId];
    if (messages == null) return;

    final index = messages.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      messages[index] = message;
      await _persistMessages(message.chatId);
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
        await setActiveChat(detail.id);
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
    await _persistMessages(created.id);
    return created;
  }

  Future<void> setActiveChat(String chatId) async {
    if (_activeChatId == chatId && _messages.containsKey(chatId)) return;
    await _persistAndEvictOtherChats(keepChatId: chatId);
    await _ensureMessagesLoaded(chatId);
    _activeChatId = chatId;
  }

  Future<void> clearInMemoryMessageCache() async {
    await _persistAndEvictOtherChats();
    _messages.clear();
    _activeChatId = null;
  }

  void dispose() {
    _client.close();
  }

  List<Chat> _sortChats(List<Chat> chats) {
    return List<Chat>.from(chats)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  void _hydrateChatCache(List<Chat> chats) {
    _chatCache
      ..clear()
      ..addEntries(chats.map((c) => MapEntry(c.id, c)));
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

  String? _extractGeneratedTitle(dynamic decoded) {
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);

    final direct = map['title'];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString();
    }

    final data = map['data'];
    if (data is Map) {
      final dataMap = Map<String, dynamic>.from(data);
      final fromData = dataMap['title'];
      if (fromData != null && fromData.toString().trim().isNotEmpty) {
        return fromData.toString();
      }
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

  Future<Directory> _ensureMessageCacheDir() async {
    if (_messageCacheDir != null) {
      return _messageCacheDir!;
    }
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'chat_message_cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _messageCacheDir = dir;
    return dir;
  }

  Future<String> _messageCachePath(String chatId) async {
    final dir = await _ensureMessageCacheDir();
    return p.join(dir.path, '${Uri.encodeComponent(chatId)}.json');
  }

  Future<void> _persistAndEvictOtherChats({String? keepChatId}) async {
    final ids = _messages.keys.toList();
    for (final id in ids) {
      if (keepChatId != null && id == keepChatId) continue;
      await _persistMessages(id);
      _messages.remove(id);
    }
  }

  Future<void> _ensureMessagesLoaded(String chatId) async {
    if (_messages.containsKey(chatId)) return;
    final loaded = await _readMessagesFromDisk(chatId);
    _messages[chatId] = loaded;
  }

  Future<List<Message>> _loadMessagesForInactiveChat(String chatId) async {
    final loaded = await _readMessagesFromDisk(chatId);
    return List<Message>.from(loaded);
  }

  Future<void> _ensureActiveForMutation(String chatId) async {
    if (_activeChatId == chatId && _messages.containsKey(chatId)) return;
    await setActiveChat(chatId);
  }

  Future<void> _persistMessages(String chatId) async {
    final messages = _messages[chatId] ?? const <Message>[];
    final path = await _messageCachePath(chatId);
    final file = File(path);
    final payload = jsonEncode(messages.map((m) => m.toMap()).toList());
    await file.writeAsString(payload, flush: true);
  }

  Future<List<Message>> _readMessagesFromDisk(String chatId) async {
    final path = await _messageCachePath(chatId);
    final file = File(path);
    if (!await file.exists()) {
      return <Message>[];
    }
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <Message>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Message>[];
      return decoded
          .whereType<Map>()
          .map((e) => Message.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[ChatRepository] failed to read cached messages: $e');
      return <Message>[];
    }
  }

  Future<void> _deleteMessagesFromDisk(String chatId) async {
    final path = await _messageCachePath(chatId);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String> _chatListCachePath() async {
    final dir = await _ensureMessageCacheDir();
    final project = await _effectiveProjectName();
    return p.join(dir.path, 'chat_list_${Uri.encodeComponent(project)}.json');
  }

  Future<List<Chat>> _readChatsFromDisk() async {
    final path = await _chatListCachePath();
    final file = File(path);
    if (!await file.exists()) {
      return <Chat>[];
    }
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <Chat>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Chat>[];
      return decoded
          .whereType<Map>()
          .map((e) => Chat.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[ChatRepository] failed to read local chats: $e');
      return <Chat>[];
    }
  }

  Future<void> _writeChatsToDisk(List<Chat> chats) async {
    final path = await _chatListCachePath();
    final file = File(path);
    final payload = jsonEncode(chats.map((c) => c.toMap()).toList());
    await file.writeAsString(payload, flush: true);
  }

  Future<void> _upsertLocalChat(Chat chat) async {
    final chats = await _readChatsFromDisk();
    final idx = chats.indexWhere((c) => c.id == chat.id);
    if (idx == -1) {
      chats.add(chat);
    } else {
      chats[idx] = chat;
    }
    await _writeChatsToDisk(_sortChats(chats));
  }

  Future<void> _removeLocalChat(String chatId) async {
    final chats = await _readChatsFromDisk();
    chats.removeWhere((c) => c.id == chatId);
    await _writeChatsToDisk(_sortChats(chats));
  }

  Future<Chat?> _getLocalChatById(String chatId) async {
    final chats = await _readChatsFromDisk();
    for (final chat in chats) {
      if (chat.id == chatId) return chat;
    }
    return null;
  }
}
