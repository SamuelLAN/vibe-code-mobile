import 'dart:convert';

enum StreamElementType {
  text,
  functionCall,
  functionResult,
  thinking,
  insightStart,
  insightEnd,
  edge,
}

String generateStreamElementId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${_streamElementSeed++}';

int _streamElementSeed = 0;

class StreamElement {
  StreamElement({
    required this.id,
    required this.type,
    required this.content,
    required this.isComplete,
    this.metadata,
  });

  final String id;
  final StreamElementType type;
  String content;
  bool isComplete;
  Map<String, dynamic>? metadata;

  StreamElement copyWith({
    String? id,
    StreamElementType? type,
    String? content,
    bool? isComplete,
    Map<String, dynamic>? metadata,
  }) {
    return StreamElement(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      isComplete: isComplete ?? this.isComplete,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'content': content,
        'isComplete': isComplete,
        'metadata': metadata,
      };

  static StreamElement fromMap(Map<String, dynamic> map) {
    final typeText = map['type']?.toString() ?? StreamElementType.text.name;
    final type = StreamElementType.values.firstWhere(
      (e) => e.name == typeText,
      orElse: () => StreamElementType.text,
    );
    final metadata = map['metadata'];
    return StreamElement(
      id: map['id']?.toString() ?? generateStreamElementId(),
      type: type,
      content: map['content']?.toString() ?? '',
      isComplete: map['isComplete'] == true,
      metadata: metadata is Map<String, dynamic>
          ? metadata
          : (metadata is Map
              ? metadata.map((k, v) => MapEntry(k.toString(), v))
              : null),
    );
  }

  @override
  String toString() => jsonEncode({
        'id': id,
        'type': type.name,
        'content': content,
        'isComplete': isComplete,
        'metadata': metadata,
      });
}
