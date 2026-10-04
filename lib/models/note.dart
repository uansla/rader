class Note {
  final int? id;
  final int bookId;
  final int chapterIdx;
  final int position;
  final int endPosition;
  final String quote;
  final String text;
  final DateTime createdAt;

  Note({
    this.id,
    required this.bookId,
    required this.chapterIdx,
    required this.position,
    this.endPosition = 0,
    this.quote = '',
    required this.text,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'chapter_idx': chapterIdx,
      'position': position,
      'end_position': endPosition,
      'quote': quote,
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
      endPosition: (map['end_position'] as int?) ?? 0,
      quote: (map['quote'] as String?) ?? '',
      text: (map['text'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as int?) ?? 0),
    );
  }
}
