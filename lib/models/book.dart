class Book {
  final int? id;
  final String title;
  final String author;
  final String format;
  final String type;
  final String path;
  final int fileSize;
  final String? cover;
  final String description;
  final String tags;
  final bool isFavorite;
  final DateTime addedAt;
  DateTime? lastReadAt;
  final int totalChapters;
  int chapterIndex;
  int position;
  double progress;
  int readMinutes;
  bool completed;
  int coverColor;

  Book({
    this.id,
    required this.title,
    this.author = '',
    required this.format,
    required this.type,
    required this.path,
    this.fileSize = 0,
    this.cover,
    this.description = '',
    this.tags = '',
    this.isFavorite = false,
    required this.addedAt,
    this.lastReadAt,
    this.totalChapters = 0,
    this.chapterIndex = 0,
    this.position = 0,
    this.progress = 0,
    this.readMinutes = 0,
    this.completed = false,
    this.coverColor = -1,
  });

  bool get isAudio => type == 'audio';
  bool get isText => type == 'text';

  Book copyWith({
    int? id,
    String? title,
    String? author,
    String? format,
    String? type,
    String? path,
    int? fileSize,
    String? cover,
    String? description,
    String? tags,
    bool? isFavorite,
    DateTime? addedAt,
    DateTime? lastReadAt,
    int? totalChapters,
    int? chapterIndex,
    int? position,
    double? progress,
    int? readMinutes,
    bool? completed,
    int? coverColor,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      format: format ?? this.format,
      type: type ?? this.type,
      path: path ?? this.path,
      fileSize: fileSize ?? this.fileSize,
      cover: cover ?? this.cover,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      addedAt: addedAt ?? this.addedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      totalChapters: totalChapters ?? this.totalChapters,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      position: position ?? this.position,
      progress: progress ?? this.progress,
      readMinutes: readMinutes ?? this.readMinutes,
      completed: completed ?? this.completed,
      coverColor: coverColor ?? this.coverColor,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'format': format,
      'type': type,
      'path': path,
      'file_size': fileSize,
      'cover': cover,
      'description': description,
      'tags': tags,
      'is_favorite': isFavorite ? 1 : 0,
      'added_at': addedAt.millisecondsSinceEpoch,
      'last_read_at': lastReadAt?.millisecondsSinceEpoch,
      'total_chapters': totalChapters,
      'chapter_index': chapterIndex,
      'position': position,
      'progress': progress,
      'read_minutes': readMinutes,
      'completed': completed ? 1 : 0,
      'cover_color': coverColor,
    };
  }

  factory Book.fromMap(Map<String, Object?> map) {
    return Book(
      id: map['id'] as int?,
      title: map['title'] as String,
      author: (map['author'] as String?) ?? '',
      format: map['format'] as String,
      type: map['type'] as String,
      path: map['path'] as String,
      fileSize: (map['file_size'] as int?) ?? 0,
      cover: map['cover'] as String?,
      description: (map['description'] as String?) ?? '',
      tags: (map['tags'] as String?) ?? '',
      isFavorite: (map['is_favorite'] as int?) == 1,
      addedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['added_at'] as int?) ?? 0),
      lastReadAt: map['last_read_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_read_at'] as int)
          : null,
      totalChapters: (map['total_chapters'] as int?) ?? 0,
      chapterIndex: (map['chapter_index'] as int?) ?? 0,
      position: (map['position'] as int?) ?? 0,
      progress: ((map['progress'] as num?) ?? 0).toDouble(),
      readMinutes: (map['read_minutes'] as int?) ?? 0,
      completed: (map['completed'] as int?) == 1,
      coverColor: (map['cover_color'] as int?) ?? -1,
    );
  }
}
