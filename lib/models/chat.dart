class Chat {
  Chat({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessagePreview,
  });

  final String id;
  String title;
  DateTime createdAt;
  DateTime updatedAt;
  String? lastMessagePreview;

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastMessagePreview': lastMessagePreview,
      };

  static Chat fromMap(Map<String, dynamic> map) => Chat(
        id: map['id'] as String,
        title: map['title'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
        lastMessagePreview: map['lastMessagePreview'] as String?,
      );
}
