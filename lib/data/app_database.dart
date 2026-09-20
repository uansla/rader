import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  AppDatabase._();
  static Database? _db;
  static String? _dbPath;

  static String? get dbPath => _dbPath;

  static Future<Database> get instance async {
    _db ??= await _open();
    return _db!;
  }

  static Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  static Future<Database> _open() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'reader.db');
    _dbPath = dbPath;
    return openDatabase(
      dbPath,
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final bookCols = {
        for (final r in await db.rawQuery('PRAGMA table_info(books)')) r['name'] as String
      };
      if (!bookCols.contains('read_minutes')) {
        await db.execute(
            'ALTER TABLE books ADD COLUMN read_minutes INTEGER DEFAULT 0');
      }
      if (!bookCols.contains('completed')) {
        await db.execute(
            'ALTER TABLE books ADD COLUMN completed INTEGER DEFAULT 0');
      }
      if (!bookCols.contains('cover_color')) {
        await db.execute(
            'ALTER TABLE books ADD COLUMN cover_color INTEGER DEFAULT -1');
      }
      await db.execute('''
        CREATE TABLE IF NOT EXISTS read_daily (
          date TEXT PRIMARY KEY,
          minutes INTEGER DEFAULT 0
        )
      ''');
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        author TEXT DEFAULT '',
        format TEXT NOT NULL,
        type TEXT NOT NULL,
        path TEXT NOT NULL UNIQUE,
        file_size INTEGER DEFAULT 0,
        cover TEXT,
        description TEXT DEFAULT '',
        tags TEXT DEFAULT '',
        is_favorite INTEGER DEFAULT 0,
        added_at INTEGER,
        last_read_at INTEGER,
        total_chapters INTEGER DEFAULT 0,
        chapter_index INTEGER DEFAULT 0,
        position INTEGER DEFAULT 0,
        progress REAL DEFAULT 0,
        read_minutes INTEGER DEFAULT 0,
        completed INTEGER DEFAULT 0,
        cover_color INTEGER DEFAULT -1
      )
    ''');
    await db.execute('''
      CREATE TABLE chapters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        idx INTEGER NOT NULL,
        title TEXT NOT NULL,
        offset INTEGER DEFAULT 0,
        end_offset INTEGER DEFAULT 0,
        duration INTEGER DEFAULT 0,
        file_path TEXT,
        UNIQUE(book_id, idx)
      )
    ''');
    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        chapter_idx INTEGER DEFAULT 0,
        position INTEGER DEFAULT 0,
        text TEXT DEFAULT '',
        created_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        chapter_idx INTEGER DEFAULT 0,
        position INTEGER DEFAULT 0,
        text TEXT DEFAULT '',
        created_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE library_folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        enabled INTEGER DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE reading_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        action TEXT DEFAULT 'read',
        chapter_idx INTEGER DEFAULT 0,
        position INTEGER DEFAULT 0,
        ts INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE read_daily (
        date TEXT PRIMARY KEY,
        minutes INTEGER DEFAULT 0
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_books_type ON books(type)');
    await db.execute(
        'CREATE INDEX idx_chapters_book ON chapters(book_id)');
  }
}
