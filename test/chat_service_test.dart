import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_code_mobile/models/attachment.dart';
import 'package:vibe_code_mobile/services/chat_repository.dart';
import 'package:vibe_code_mobile/services/chat_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('chat service creates chats and messages', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final tempDir = await Directory.systemTemp.createTemp('vibe_test');
    final repo = ChatRepository(dbPath: '${tempDir.path}/test.db', factory: databaseFactory);
    final service = ChatService(repository: repo);

    await service.initialize();
    expect(service.chats.isNotEmpty, isTrue);

    await service.sendUserMessage('Hello world', <Attachment>[]);
    expect(service.messages.length, greaterThanOrEqualTo(2));
  });
}
