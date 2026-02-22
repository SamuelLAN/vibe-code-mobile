import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/chat.dart';
import '../models/message.dart';

class ChatRepository {
  ChatRepository({DatabaseFactory? factory, String? dbPath})\n      : _factory = factory,\n        _dbPathOverride = dbPath;

  static const _dbName = 'vibe_chat.db';
  static const _dbVersion = 1;

  Database? _db;
  final DatabaseFactory? _factory;
  final String? _dbPathOverride;

  Future<void> init() async {
    if (_db != null) return;
    final dbPath = _dbPathOverride ?? p.join((await getApplicationDocumentsDirectory()).path, _dbName);
    final factory = _factory ?? databaseFactory;
    _db = await factory.openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chats (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            lastMessagePreview TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            chatId TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            attachments TEXT,
            FOREIGN KEY(chatId) REFERENCES chats(id) ON DELETE CASCADE
          )
        ''');
      },
    );
  }

  Future<List<Chat>> getChats() async {
    final db = _db!;
    final rows = await db.query('chats', orderBy: 'updatedAt DESC');
    return rows.map(Chat.fromMap).toList();
  }

  Future<Chat> createChat(Chat chat) async {
    final db = _db!;
    await db.insert('chats', chat.toMap());
    return chat;
  }

  Future<void> updateChat(Chat chat) async {
    final db = _db!;
    await db.update('chats', chat.toMap(), where: 'id = ?', whereArgs: [chat.id]);
  }

  Future<void> deleteChat(String chatId) async {
    final db = _db!;
    await db.delete('messages', where: 'chatId = ?', whereArgs: [chatId]);
    await db.delete('chats', where: 'id = ?', whereArgs: [chatId]);
  }

  Future<List<Message>> getMessages(String chatId) async {
    final db = _db!;
    final rows = await db.query(
      'messages',
      where: 'chatId = ?',
      whereArgs: [chatId],
      orderBy: 'createdAt ASC',
    );
    return rows.map(Message.fromMap).toList();
  }

  Future<void> addMessage(Message message) async {
    final db = _db!;
    await db.insert('messages', message.toMap());
  }
}
