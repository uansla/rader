import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../data/repositories.dart';
import '../models/book.dart';

/// 书架进度 / 标注数据的导出与合并导入。
/// 进度按书路径（path）匹配；导入时保留时间更新的进度。
class SyncService {
  final BookRepository books;
  final BookmarkRepository bookmarks;
  final NoteRepository notes;

  SyncService({required this.books, required this.bookmarks, required this.notes});

  static const _appTag = 'reader-progress';

  Future<String> exportJson() async {
    final list = <Map<String, Object?>>[];
    for (final b in await books.getAll()) {
      list.add({
        'path': b.path,
        'title': b.title,
        'format': b.format,
        'type': b.type,
        'file_size': b.fileSize,
        'chapter_index': b.chapterIndex,
        'position': b.position,
        'progress': b.progress,
        'last_read_at': b.lastReadAt?.millisecondsSinceEpoch,
        'completed': b.completed,
      });
    }
    return json.encode({
      'app': _appTag,
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'books': list,
    });
  }

  Future<String> exportToFile() async {
    final path = await _pickSave();
    if (path == null) return '已取消';
    try {
      await File(path).writeAsString(await exportJson(), encoding: utf8);
      return '已导出进度到：$path';
    } catch (e) {
      return '导出失败：$e';
    }
  }

  Future<String> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (result == null || result.files.isEmpty) return '已取消';
    final path = result.files.first.path;
    if (path == null) return '已取消';
    try {
      final text = await File(path).readAsString(encoding: utf8);
      return await importJson(text);
    } catch (e) {
      return '导入失败：$e';
    }
  }

  Future<String> importJson(String text) async {
    final root = json.decode(text);
    if (root is! Map || root['app'] != _appTag) {
      return '不是有效的 Reader 进度文件';
    }
    final items = (root['books'] as List?) ?? const [];
    final allBooks = await books.getAll();
    var updated = 0;
    var added = 0;
    var skipped = 0;
    for (final raw in items) {
      final m = raw as Map<String, Object?>;
      final path = (m['path'] as String?) ?? '';
      final ts = (m['last_read_at'] as int?) ?? 0;
      // 先按路径匹配，路径对不上时退回「书名 + 格式 + 大小」匹配，
      // 这样换设备 / 换目录也能对上进度。
      var existing = path.isEmpty ? null : await books.getByPath(path);
      existing ??= _matchByMeta(allBooks, m);
      if (existing != null) {
        final mine = existing.lastReadAt?.millisecondsSinceEpoch ?? 0;
        if (ts >= mine) {
          await books.touch(existing.id!,
              chapterIdx: (m['chapter_index'] as int?) ?? existing.chapterIndex,
              position: (m['position'] as int?) ?? existing.position,
              progress: ((m['progress'] as num?) ?? existing.progress).toDouble());
          if (m['completed'] == true && !existing.completed) {
            await books.setCompleted(existing.id!, true);
          }
          updated++;
        } else {
          skipped++;
        }
      } else {
        await books.insert(Book(
          title: (m['title'] as String?) ?? '导入书籍',
          format: (m['format'] as String?) ?? 'txt',
          type: (m['type'] as String?) ?? 'text',
          path: path,
          chapterIndex: (m['chapter_index'] as int?) ?? 0,
          position: (m['position'] as int?) ?? 0,
          progress: ((m['progress'] as num?) ?? 0).toDouble(),
          completed: m['completed'] == true,
          addedAt: DateTime.now(),
          lastReadAt: ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts) : null,
        ));
        added++;
      }
    }
    return '导入完成：更新 $updated 本，新增 $added 本，跳过 $skipped 本';
  }

  Future<String?> _pickSave() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '导出书架进度',
      fileName: 'reader_progress_${DateTime.now().millisecondsSinceEpoch}.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (result == null || result.isEmpty) return null;
    return result;
  }

  Book? _matchByMeta(List<Book> all, Map<String, Object?> m) {
    final title = ((m['title'] as String?) ?? '').trim();
    final format = (m['format'] as String?) ?? '';
    if (title.isEmpty) return null;
    final size = (m['file_size'] as int?) ?? 0;
    Book? byTitle;
    for (final b in all) {
      if (b.title.trim() == title && b.format == format) {
        if (size > 0 && b.fileSize == size) return b;
        byTitle ??= b;
      }
    }
    return byTitle;
  }
}

/// 生成 Markdown 标注导出（按书按章组织）。
class MarkdownExporter {
  final BookRepository books;
  final BookmarkRepository bookmarks;
  final NoteRepository notes;

  MarkdownExporter(
      {required this.books, required this.bookmarks, required this.notes});

  Future<String> buildForBook(int bookId, List<String> chapterTitles) async {
    final b = await books.getById(bookId);
    if (b == null) return '';
    final buf = StringBuffer();
    buf.writeln('# ${b.title}');
    buf.writeln();
    final bms = await bookmarks.getForBook(bookId);
    final ns = await notes.getForBook(bookId);
    if (bms.isNotEmpty) {
      buf.writeln('## 书签');
      for (final bm in bms) {
        final title = _chapterTitle(bm.chapterIdx, chapterTitles);
        buf.writeln(
            '- [${_date(bm.createdAt)}] 第${bm.chapterIdx + 1}章 $title  ${_snip(bm.text)}');
      }
      buf.writeln();
    }
    if (ns.isNotEmpty) {
      buf.writeln('## 笔记');
      for (final n in ns) {
        final title = _chapterTitle(n.chapterIdx, chapterTitles);
        buf.writeln('- [${_date(n.createdAt)}] 第${n.chapterIdx + 1}章 $title');
        buf.writeln();
        buf.writeln('  > ${n.text.replaceAll('\n', '\n  > ')}');
        buf.writeln();
      }
    }
    if (bms.isEmpty && ns.isEmpty) {
      buf.writeln('*暂无标注*');
    }
    return buf.toString();
  }

  static String _chapterTitle(int idx, List<String> titles) {
    if (titles.isNotEmpty && idx < titles.length) return titles[idx];
    return '';
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _snip(String s) {
    final t = s.trim().replaceAll('\n', ' ');
    return t.length > 30 ? '${t.substring(0, 30)}…' : t;
  }
}
