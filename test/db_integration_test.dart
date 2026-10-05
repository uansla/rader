import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:reader/data/app_database.dart';
import 'package:reader/data/repositories.dart';
import 'package:reader/models/book.dart';
import 'package:reader/models/note.dart';
import 'package:reader/services/scanner_service.dart';
import 'package:reader/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String root;
  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('reader_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await AppDatabase.close();
  });

  tearDownAll(() async {
    await AppDatabase.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('v4 schema: notes keep selected quote range', () async {
    final db = await AppDatabase.instance;
    final tables = (await db
            .rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((r) => r['name'])
        .toList();
    expect(tables, containsAll(['read_daily', 'hidden_books']));

    final cols = await db.rawQuery('PRAGMA table_info(books)');
    final names = cols.map((c) => c['name']).toSet();
    expect(names, containsAll(['read_minutes', 'completed', 'cover_color']));

    final noteCols = await db.rawQuery('PRAGMA table_info(notes)');
    final noteNames = noteCols.map((c) => c['name']).toSet();
    expect(noteNames, containsAll(['quote', 'end_position']));
  });

  test('ReadDailyRepository accumulates minutes and queries range', () async {
    final repo = ReadDailyRepository();
    final d1 = DateTime(2026, 1, 1);
    final d2 = DateTime(2026, 1, 2);
    await repo.addMinutes(d1, 5);
    await repo.addMinutes(d1, 10);
    await repo.addMinutes(d2, 3);
    expect(await repo.minutesOn(d1), 15);
    expect(await repo.minutesOn(d2), 3);
    final range = await repo.range(d1, d2);
    expect(range['2026-01-01'], 15);
    expect(range['2026-01-02'], 3);
  });

  test('BookRepository new methods: readMinutes/completed/coverColor/info',
      () async {
    final repo = BookRepository();
    final book = Book(
      title: '测试书',
      format: 'txt',
      type: 'text',
      path: 'C:/a/测试书.txt',
      addedAt: DateTime(2026, 1, 1),
    );
    final id = await repo.insert(book);
    await repo.addReadMinutes(id, 7);
    await repo.setCompleted(id, true);
    await repo.setCoverColor(id, 3);
    await repo.setInfo(id, title: '新书名', author: '作者甲', tags: '玄幻,热血');

    final updated = await repo.getById(id);
    expect(updated, isNotNull);
    expect(updated!.readMinutes, 7);
    expect(updated.completed, isTrue);
    expect(updated.coverColor, 3);
    expect(updated.title, '新书名');
    expect(updated.author, '作者甲');
    expect(updated.tags, '玄幻,热血');
  });

  test('BookRepository clear record keeps hidden path for rescans', () async {
    final repo = BookRepository();
    final book = Book(
      title: '待清理',
      format: 'txt',
      type: 'text',
      path: 'C:/reader/books/待清理.txt',
      addedAt: DateTime(2026, 1, 1),
    );
    final id = await repo.insert(book);
    expect(await repo.getById(id), isNotNull);

    await repo.delete(id);

    expect(await repo.getById(id), isNull);
    final excluded = await repo.getExcludedPaths();
    expect(excluded.single.toLowerCase(), contains('待清理.txt'));
  });

  test('BookRepository delete can remove without hiding path', () async {
    final repo = BookRepository();
    final book = Book(
      title: '可重新扫描',
      format: 'txt',
      type: 'text',
      path: 'C:/reader/books/可重新扫描.txt',
      addedAt: DateTime(2026, 1, 1),
    );
    final id = await repo.insert(book);
    await repo.deleteMany([id], hideFromRescan: false);

    expect(await repo.getById(id), isNull);
    final excluded = await repo.getExcludedPaths();
    expect(
      excluded.contains('c:/reader/books/可重新扫描.txt'),
      isFalse,
    );
  });

  test('scanner keeps record when source file is temporarily unavailable', () async {
    final repo = BookRepository();
    final chapters = ChapterRepository();
    final scanDir = Directory(p.join(
      tmp.path,
      'missing_source_${DateTime.now().microsecondsSinceEpoch}',
    ));
    await scanDir.create(recursive: true);
    final sourcePath = p.join(scanDir.path, '离线文件.txt');
    final id = await repo.insert(Book(
      title: '离线文件',
      format: 'txt',
      type: 'text',
      path: sourcePath,
      addedAt: DateTime(2026, 1, 1),
    ));

    final scanner = ScannerService(repo, chapters);
    await scanner.scanDirectories([scanDir.path]);

    expect(await repo.getById(id), isNotNull);
  });

  test('SyncService merge: meta fallback match when path differs', () async {
    final repo = BookRepository();
    await repo.insert(Book(
      title: '测试书',
      format: 'txt',
      type: 'text',
      path: 'C:/local/测试书.txt',
      addedAt: DateTime(2026, 1, 1),
    ));
    final svc = SyncService(
      books: repo,
      bookmarks: BookmarkRepository(),
      notes: NoteRepository(repo),
    );
    // 导入文件里路径不同，但书名+格式一致 → 应通过元数据匹配到本机书并更新进度
    const json = '{"app":"reader-progress","version":1,"books":['
        '{"path":"D:/other/测试书.txt","title":"测试书","format":"txt",'
        '"file_size":0,"chapter_index":5,"position":100,"progress":0.5,'
        '"last_read_at":2000000000000,"completed":true}]}';
    final msg = await svc.importJson(json);
    expect(msg, contains('更新'));

    final updated = await repo.getByPath('C:/local/测试书.txt');
    expect(updated, isNotNull);
    expect(updated!.chapterIndex, 5);
    expect(updated.position, 100);
    expect(updated.completed, isTrue);
  });

  test('SyncService merge: brand-new book gets added', () async {
    final repo = BookRepository();
    final svc = SyncService(
      books: repo,
      bookmarks: BookmarkRepository(),
      notes: NoteRepository(repo),
    );
    const json = '{"app":"reader-progress","version":1,"books":['
        '{"path":"Z:/books/全新.txt","title":"全新","format":"txt",'
        '"file_size":0,"chapter_index":0,"position":0,"progress":0.1,'
        '"last_read_at":1000000000000,"completed":false}]}';
    final msg = await svc.importJson(json);
    expect(msg, contains('新增'));

    final added = await repo.getByPath('Z:/books/全新.txt');
    expect(added, isNotNull);
    expect(added!.progress, closeTo(0.1, 0.001));
  });

  test('NoteRepository writes notes to external files', () async {
    final books = BookRepository();
    final repo = NoteRepository(books);
    final notesDir = Directory(p.join(tmp.path, 'reader_notes'));
    await notesDir.create(recursive: true);
    repo.configure(notesDir.path);

    final bookId = await books.insert(Book(
      title: '外部笔记测试',
      format: 'txt',
      type: 'text',
      path: 'C:/reader/外部笔记测试.txt',
      addedAt: DateTime(2026, 1, 1),
    ));

    await repo.add(Note(
      bookId: bookId,
      chapterIdx: 0,
      position: 12,
      endPosition: 28,
      quote: '这是被选择并标记的原文',
      text: '原始笔记',
      createdAt: DateTime(2026, 1, 1),
    ));

    final list = await repo.getForBook(bookId);
    expect(list.single.text, '原始笔记');
    expect(list.single.quote, '这是被选择并标记的原文');
    expect(list.single.endPosition, 28);

    final files = notesDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.reader-notes.json'))
        .toList();
    expect(files, hasLength(1));
    final raw = await files.single.readAsString(encoding: utf8);
    expect(raw, contains('这是被选择并标记的原文'));
    expect(raw, contains('原始笔记'));

    final db = await AppDatabase.instance;
    final dbRows = await db.query('notes');
    expect(dbRows, isEmpty);

    await repo.update(Note(
      id: list.single.id,
      bookId: bookId,
      chapterIdx: list.single.chapterIdx,
      position: list.single.position,
      endPosition: list.single.endPosition,
      quote: list.single.quote,
      text: '修改后的笔记',
      createdAt: list.single.createdAt,
    ));
    final updated = await repo.getForBook(bookId);
    expect(updated.single.text, '修改后的笔记');
    expect(updated.single.quote, '这是被选择并标记的原文');
  });
}
