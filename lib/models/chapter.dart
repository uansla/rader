class Chapter {
  final int? id;
  final int bookId;
  final int idx;
  final String title;
  final int offset;
  final int endOffset;
  final int duration;
  final String? filePath;

  Chapter({
    this.id,
    required this.bookId,
    required this.idx,
    required this.title,
    this.offset = 0,
    this.endOffset = 0,
    this.duration = 0,
    this.filePath,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'idx': idx,
      'title': title,
      'offset': offset,
      'end_offset': endOffset,
      'duration': duration,
      'file_path': filePath,
    };
  }

  factory Chapter.fromMap(Map<String, Object?> map) {
    return Chapter(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      idx: map['idx'] as int,
      title: map['title'] as String,
      offset: (map['offset'] as int?) ?? 0,
      endOffset: (map['end_offset'] as int?) ?? 0,
      duration: (map['duration'] as int?) ?? 0,
      filePath: map['file_path'] as String?,
    );
  }
}
