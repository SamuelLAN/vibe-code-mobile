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

  @override
  String toString() => jsonEncode({
        'id': id,
        'type': type.name,
        'content': content,
        'isComplete': isComplete,
        'metadata': metadata,
      });
}
