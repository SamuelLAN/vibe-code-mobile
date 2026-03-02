import 'dart:convert';

import 'attachment.dart';
import 'stream_element.dart';

enum MessageRole { user, assistant }

class Message {
  Message({
    required this.id,
    required this.chatId,
    required this.role,
    required this.content,
    required this.createdAt,
    required this.attachments,
    this.isStreaming = false,
    List<StreamElement>? streamElements,
  }) : streamElements = streamElements ?? <StreamElement>[];

  final String id;
  final String chatId;
  final MessageRole role;
  String content;
  DateTime createdAt;
  List<Attachment> attachments;
  bool isStreaming;
  List<StreamElement> streamElements;

  Map<String, dynamic> toMap() => {
        'id': id,
        'chatId': chatId,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'attachments': attachments.map((a) => a.toMap()).toList(),
        'isStreaming': isStreaming,
        'streamElements': streamElements.map((e) => e.toMap()).toList(),
      };

  static Message fromMap(Map<String, dynamic> map) {
    final rawAttachments = map['attachments'];
    final attachments = switch (rawAttachments) {
      String value => Attachment.decodeList(value),
      List value => value
          .whereType<Map>()
          .map((e) => Attachment.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      _ => <Attachment>[],
    };

    final rawElements = map['streamElements'];
    final streamElements = switch (rawElements) {
      String value => (jsonDecode(value) as List<dynamic>)
          .whereType<Map>()
          .map((e) => StreamElement.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      List value => value
          .whereType<Map>()
          .map((e) => StreamElement.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      _ => <StreamElement>[],
    };

    return Message(
      id: map['id'] as String,
      chatId: map['chatId'] as String,
      role: MessageRole.values.firstWhere((e) => e.name == map['role']),
      content: map['content'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      attachments: attachments,
      isStreaming: map['isStreaming'] == true,
      streamElements: streamElements,
    );
  }
}
