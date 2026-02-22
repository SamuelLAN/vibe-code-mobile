import 'dart:convert';

enum AttachmentType { image, file }

class Attachment {
  Attachment({
    required this.id,
    required this.path,
    required this.name,
    required this.type,
    required this.mime,
    this.sizeBytes,
    this.uploadProgress = 1.0,
  });

  final String id;
  final String path;
  final String name;
  final AttachmentType type;
  final String mime;
  final int? sizeBytes;
  double uploadProgress;

  Map<String, dynamic> toMap() => {
        'id': id,
        'path': path,
        'name': name,
        'type': type.name,
        'mime': mime,
        'sizeBytes': sizeBytes,
      };

  static Attachment fromMap(Map<String, dynamic> map) => Attachment(
        id: map['id'] as String,
        path: map['path'] as String,
        name: map['name'] as String,
        type: AttachmentType.values.firstWhere((e) => e.name == map['type']),
        mime: map['mime'] as String,
        sizeBytes: map['sizeBytes'] as int?,
      );

  static String encodeList(List<Attachment> attachments) =>
      jsonEncode(attachments.map((a) => a.toMap()).toList());

  static List<Attachment> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => Attachment.fromMap(item as Map<String, dynamic>)).toList();
  }
}
