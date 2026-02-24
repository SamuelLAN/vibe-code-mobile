import 'dart:convert';

enum AttachmentType { image, file, voice }

/// 转录状态
enum TranscriptionStatus {
  none,     // 非语音消息
  pending,  // 等待转录
  loading,  // 转录中
  completed, // 转录完成
  error,    // 转录失败
}

class Attachment {
  Attachment({
    required this.id,
    required this.path,
    required this.name,
    required this.type,
    required this.mime,
    this.sizeBytes,
    this.uploadProgress = 1.0,
    this.transcriptionStatus = TranscriptionStatus.none,
    this.transcribedText,
  });

  final String id;
  final String path;
  final String name;
  final AttachmentType type;
  final String mime;
  final int? sizeBytes;
  double uploadProgress;
  
  /// 转录状态
  TranscriptionStatus transcriptionStatus;
  
  /// 转录文本
  String? transcribedText;

  Map<String, dynamic> toMap() => {
        'id': id,
        'path': path,
        'name': name,
        'type': type.name,
        'mime': mime,
        'sizeBytes': sizeBytes,
        'transcriptionStatus': transcriptionStatus.name,
        'transcribedText': transcribedText,
      };

  static Attachment fromMap(Map<String, dynamic> map) => Attachment(
        id: map['id'] as String,
        path: map['path'] as String,
        name: map['name'] as String,
        type: AttachmentType.values.firstWhere((e) => e.name == map['type']),
        mime: map['mime'] as String,
        sizeBytes: map['sizeBytes'] as int?,
        transcriptionStatus: TranscriptionStatus.values.firstWhere(
          (e) => e.name == map['transcriptionStatus'],
          orElse: () => TranscriptionStatus.none,
        ),
        transcribedText: map['transcribedText'] as String?,
      );

  static String encodeList(List<Attachment> attachments) =>
      jsonEncode(attachments.map((a) => a.toMap()).toList());

  static List<Attachment> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => Attachment.fromMap(item as Map<String, dynamic>)).toList();
  }

  Attachment copyWith({
    String? id,
    String? path,
    String? name,
    AttachmentType? type,
    String? mime,
    int? sizeBytes,
    double? uploadProgress,
    TranscriptionStatus? transcriptionStatus,
    String? transcribedText,
  }) {
    return Attachment(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      type: type ?? this.type,
      mime: mime ?? this.mime,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      transcriptionStatus: transcriptionStatus ?? this.transcriptionStatus,
      transcribedText: transcribedText ?? this.transcribedText,
    );
  }
}
