import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:path/path.dart' as p;

import '../data/repositories.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import 'text_parser.dart';
import 'docx_parser.dart';
import 'odt_parser.dart';

class BookSession {
  final int bookId;
  final List<String> titles;
  final List<String> texts;
  BookSession(this.bookId, this.titles, this.texts);
}

class TextContentService {
  final ChapterRepository _chapterRepo;

  TextContentService(this._chapterRepo);

  Future<BookSession> open(Book book) async {
    if (book.format == 'epub') {
      return _openEpub(book);
    }

    final bytes = await File(book.path).readAsBytes();

    // ODT/DOCX are ZIP-based XML office documents. Convert them to plain text
    // first, then feed the result through the existing chapter splitter.
    if (book.format == 'odt' || book.format == 'docx') {
      final content = book.format == 'odt'
          ? await OdtParser.parse(bytes)
          : await DocxParser.parse(bytes);
      final chapters = TextParser.splitChapters(content);
      final texts = [
        for (final c in chapters) content.substring(c.start, c.end),
      ];
      await _persist(book.id!, chapters, book.format);
      return BookSession(
        book.id!,
        chapters.map((c) => c.title).toList(),
        texts,
      );
    }

    final parsed = await TextParser.parseBytes(bytes);
    final texts = <String>[];
    for (final c in parsed.chapters) {
      var t = parsed.content.substring(c.start, c.end);
      if (book.format == 'html' || book.format == 'fb2') {
        t = TextParser.stripHtml(t);
      }
      texts.add(t);
    }
    await _persist(book.id!, parsed.chapters, book.format);
    return BookSession(book.id!, parsed.chapters.map((c) => c.title).toList(), texts);
  }

  Future<BookSession> _openEpub(Book book) async {
    final bytes = await File(book.path).readAsBytes();
    final epub = await EpubReader.readBook(bytes);
    final flat = <EpubChapter>[];
    for (final c in epub.Chapters ?? []) {
      _flatten(c, flat);
    }
    final titles = <String>[];
    final texts = <String>[];
    for (final c in flat) {
      final title = (c.Title?.trim().isNotEmpty ?? false)
          ? c.Title!.trim()
          : '第${titles.length + 1}节';
      titles.add(title);
      texts.add(TextParser.stripHtml(c.HtmlContent ?? ''));
    }
    final spans = [
      for (var i = 0; i < titles.length; i++)
        ChapterSpan(titles[i], i, i + 1),
    ];
    await _persist(book.id!, spans, 'epub');
    return BookSession(book.id!, titles, texts);
  }

  void _flatten(EpubChapter c, List<EpubChapter> out) {
    out.add(c);
    for (final sub in c.SubChapters ?? []) {
      _flatten(sub, out);
    }
  }

  Future<void> _persist(int bookId, List<ChapterSpan> spans, String format) async {
    final chapters = <Chapter>[];
    for (var i = 0; i < spans.length; i++) {
      chapters.add(Chapter(
        bookId: bookId,
        idx: i,
        title: spans[i].title,
        offset: format == 'epub' ? i : spans[i].start,
        endOffset: format == 'epub' ? i + 1 : spans[i].end,
      ));
    }
    await _chapterRepo.replaceForBook(bookId, chapters);
  }

  static String bookTitleFromPath(String path) {
    final base = p.basenameWithoutExtension(path);
    return base;
  }
}
