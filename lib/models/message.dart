import 'attachment.dart';

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
  });

  final String id;
  final String chatId;
  final MessageRole role;
  String content;
  DateTime createdAt;
  List<Attachment> attachments;
  bool isStreaming;

  Map<String, dynamic> toMap() => {
        'id': id,
        'chatId': chatId,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'attachments': Attachment.encodeList(attachments),
      };

  static Message fromMap(Map<String, dynamic> map) => Message(
        id: map['id'] as String,
        chatId: map['chatId'] as String,
        role: MessageRole.values.firstWhere((e) => e.name == map['role']),
        content: map['content'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        attachments: Attachment.decodeList(map['attachments'] as String?),
      );
}
