import 'package:sqflite/sqflite.dart';

import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/chapter.dart';
import '../models/library_folder.dart';
import '../models/note.dart';
import 'app_database.dart';

class BookRepository {
  Future<List<Book>> getAll() async {
    final db = await AppDatabase.instance;
    final rows = await db.query('books', orderBy: 'last_read_at DESC');
    return rows.map(Book.fromMap).toList();
  }

  Future<Book?> getById(int id) async {
    final db = await AppDatabase.instance;
    final rows = await db.query('books', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Book.fromMap(rows.first);
  }

  Future<Book?> getByPath(String path) async {
    final db = await AppDatabase.instance;
    final rows = await db.query('books', where: 'path = ?', whereArgs: [path]);
    if (rows.isEmpty) return null;
    return Book.fromMap(rows.first);
  }

  Future<int> insert(Book book) async {
    final db = await AppDatabase.instance;
    return db.insert('books', book.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> update(Book book) async {
    final db = await AppDatabase.instance;
    await db.update('books', book.toMap(),
        where: 'id = ?', whereArgs: [book.id]);
  }

  Future<void> delete(int id) async {
    final db = await AppDatabase.instance;
    await db.transaction((txn) async {
      await txn.delete('chapters', where: 'book_id = ?', whereArgs: [id]);
      await txn.delete('bookmarks', where: 'book_id = ?', whereArgs: [id]);
      await txn.delete('notes', where: 'book_id = ?', whereArgs: [id]);
      await txn.delete('reading_history',
          where: 'book_id = ?', whereArgs: [id]);
      await txn.delete('books', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> setFavorite(int id, bool fav) async {
    final db = await AppDatabase.instance;
    await db.update('books', {'is_favorite': fav ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> touch(int id, {int? chapterIdx, int? position, double? progress}) async {
    final db = await AppDatabase.instance;
    final fields = <String, Object?>{'last_read_at': DateTime.now().millisecondsSinceEpoch};
    if (chapterIdx != null) fields['chapter_index'] = chapterIdx;
    if (position != null) fields['position'] = position;
    if (progress != null) fields['progress'] = progress;
    await db.update('books', fields, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addReadMinutes(int id, int minutes) async {
    if (minutes <= 0) return;
    final db = await AppDatabase.instance;
    await db.rawUpdate(
        'UPDATE books SET read_minutes = read_minutes + ? WHERE id = ?',
        [minutes, id]);
  }

  Future<void> setCompleted(int id, bool completed) async {
    final db = await AppDatabase.instance;
    await db.update('books', {'completed': completed ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setCoverColor(int id, int color) async {
    final db = await AppDatabase.instance;
    await db.update('books', {'cover_color': color},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setInfo(int id,
      {String? title, String? author, String? tags}) async {
    final db = await AppDatabase.instance;
    final fields = <String, Object?>{};
    if (title != null && title.isNotEmpty) fields['title'] = title;
    if (author != null) fields['author'] = author;
    if (tags != null) fields['tags'] = tags;
    if (fields.isEmpty) return;
    await db.update('books', fields, where: 'id = ?', whereArgs: [id]);
  }
}

class ChapterRepository {
  Future<List<Chapter>> getForBook(int bookId) async {
    final db = await AppDatabase.instance;
    final rows = await db.query('chapters',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'idx ASC');
    return rows.map(Chapter.fromMap).toList();
  }

  Future<void> replaceForBook(int bookId, List<Chapter> chapters) async {
    final db = await AppDatabase.instance;
    await db.transaction((txn) async {
      await txn.delete('chapters', where: 'book_id = ?', whereArgs: [bookId]);
      for (final c in chapters) {
        await txn.insert('chapters', c.toMap());
      }
    });
  }
}

class BookmarkRepository {
  Future<List<Bookmark>> getForBook(int bookId) async {
    final db = await AppDatabase.instance;
    final rows = await db.query('bookmarks',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'position ASC');
    return rows.map(Bookmark.fromMap).toList();
  }

  Future<List<Bookmark>> getAll() async {
    final db = await AppDatabase.instance;
    final rows = await db.query('bookmarks', orderBy: 'created_at DESC');
    return rows.map(Bookmark.fromMap).toList();
  }

  Future<void> add(Bookmark bm) async {
    final db = await AppDatabase.instance;
    await db.insert('bookmarks', bm.toMap());
  }

  Future<void> remove(int id) async {
    final db = await AppDatabase.instance;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }
}

class NoteRepository {
  Future<List<Note>> getForBook(int bookId) async {
    final db = await AppDatabase.instance;
    final rows = await db.query('notes',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'created_at DESC');
    return rows.map(Note.fromMap).toList();
  }

  Future<List<Note>> getAll() async {
    final db = await AppDatabase.instance;
    final rows = await db.query('notes', orderBy: 'created_at DESC');
    return rows.map(Note.fromMap).toList();
  }

  Future<void> add(Note note) async {
    final db = await AppDatabase.instance;
    await db.insert('notes', note.toMap());
  }

  Future<void> update(Note note) async {
    final db = await AppDatabase.instance;
    await db.update('notes', {
      'text': note.text,
    }, where: 'id = ?', whereArgs: [note.id]);
  }

  Future<void> remove(int id) async {
    final db = await AppDatabase.instance;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }
}

class FolderRepository {
  Future<List<LibraryFolder>> getAll() async {
    final db = await AppDatabase.instance;
    final rows = await db.query('library_folders', orderBy: 'id ASC');
    return rows.map(LibraryFolder.fromMap).toList();
  }

  Future<void> add(String path) async {
    final db = await AppDatabase.instance;
    await db.insert('library_folders', LibraryFolder(path: path).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> remove(int id) async {
    final db = await AppDatabase.instance;
    await db.delete('library_folders', where: 'id = ?', whereArgs: [id]);
  }
}

class HistoryRepository {
  Future<void> add(int bookId,
      {String action = 'read', int chapterIdx = 0, int position = 0}) async {
    final db = await AppDatabase.instance;
    await db.insert('reading_history', {
      'book_id': bookId,
      'action': action,
      'chapter_idx': chapterIdx,
      'position': position,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, Object?>>> recent({int limit = 50}) async {
    final db = await AppDatabase.instance;
    return db.query('reading_history',
        orderBy: 'ts DESC', limit: limit);
  }

  Future<List<Map<String, Object?>>> recentWithBooks({int limit = 100}) async {
    final db = await AppDatabase.instance;
    return db.rawQuery('''
      SELECT h.id, h.action, h.chapter_idx, h.position, h.ts,
             b.title AS book_title, b.type AS book_type
      FROM reading_history h
      LEFT JOIN books b ON b.id = h.book_id
      ORDER BY h.ts DESC
      LIMIT ?
    ''', [limit]);
  }
}

class ReadDailyRepository {
  Future<void> addMinutes(DateTime date, int minutes) async {
    if (minutes <= 0) return;
    final key = _dateKey(date);
    final db = await AppDatabase.instance;
    // 版本无关的 upsert（避免旧版 SQLite 不支持 ON CONFLICT）
    final rows = await db.query('read_daily',
        columns: ['date'], where: 'date = ?', whereArgs: [key]);
    if (rows.isEmpty) {
      await db.insert('read_daily', {'date': key, 'minutes': minutes});
    } else {
      await db.rawUpdate(
          'UPDATE read_daily SET minutes = minutes + ? WHERE date = ?',
          [minutes, key]);
    }
  }

  Future<Map<String, int>> range(DateTime from, DateTime to) async {
    final db = await AppDatabase.instance;
    final rows = await db.query('read_daily',
        where: 'date >= ? AND date <= ?',
        whereArgs: [_dateKey(from), _dateKey(to)]);
    return {
      for (final r in rows) r['date'] as String: (r['minutes'] as int?) ?? 0
    };
  }

  Future<int> minutesOn(DateTime date) async {
    final db = await AppDatabase.instance;
    final rows = await db.query('read_daily',
        where: 'date = ?', whereArgs: [_dateKey(date)]);
    if (rows.isEmpty) return 0;
    return (rows.first['minutes'] as int?) ?? 0;
  }

  /// 连续阅读天数（含今天，截止到今天）。只要当天读过 >=1 分钟即算。
  Future<int> streak() async {
    final db = await AppDatabase.instance;
    final rows = await db.query('read_daily', orderBy: 'date DESC');
    final days = {
      for (final r in rows) r['date'] as String: (r['minutes'] as int?) ?? 0
    };
    var count = 0;
    var d = DateTime.now();
    while (true) {
      final m = days[_dateKey(d)];
      if (m == null || m < 1) break;
      count++;
      d = d.subtract(const Duration(days: 1));
    }
    return count;
  }

  static String _dateKey(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
