class Note {
  final int? id;
  final int bookId;
  final int chapterIdx;
  final int position;
  final String text;
  final DateTime createdAt;

  Note({
    this.id,
    required this.bookId,
    required this.chapterIdx,
    required this.position,
    required this.text,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'chapter_idx': chapterIdx,
      'position': position,
      'text': text,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Note.fromMap(Map<String, Object?> map) {
    return Note(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      chapterIdx: (map['chapter_idx'] as int?) ?? 0,
      position: (map['position'] as int?) ?? 0,
      text: (map['text'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as int?) ?? 0),
    );
  }
}
