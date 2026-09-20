import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:reader/core/app_settings.dart';
import 'package:reader/models/book.dart';
import 'package:reader/services/text_parser.dart';
import 'package:reader/services/theme_scheduler.dart';

void main() {
  test('Book round-trip', () {
    final book = Book(
      title: '测试',
      format: 'txt',
      type: 'text',
      path: '/x/a.txt',
      addedAt: DateTime(2026, 1, 1),
    );
    final restored = Book.fromMap(book.toMap());
    expect(restored.title, '测试');
    expect(restored.format, 'txt');
    expect(restored.type, 'text');
    expect(restored.path, '/x/a.txt');
  });

  test('Book round-trip keeps new humanized fields', () {
    final book = Book(
      title: '新功能',
      format: 'epub',
      type: 'text',
      path: '/x/b.epub',
      addedAt: DateTime(2026, 2, 2),
      chapterIndex: 3,
      position: 456,
      progress: 0.42,
      readMinutes: 120,
      completed: true,
      coverColor: 5,
    );
    final restored = Book.fromMap(book.toMap());
    expect(restored.chapterIndex, 3);
    expect(restored.position, 456);
    expect(restored.progress, 0.42);
    expect(restored.readMinutes, 120);
    expect(restored.completed, isTrue);
    expect(restored.coverColor, 5);
  });

  test('ReaderSettings copyWith preserves new fields', () {
    final s = ReaderSettings(
      fontSize: 20,
      dailyTarget: 45,
      pageMode: ReaderPageMode.scroll,
      themeAuto: true,
      customFontFamily: 'MyFont',
      autoBackupIntervalDays: 7,
    );
    final s2 = s.copyWith(fontSize: 24);
    expect(s2.fontSize, 24);
    expect(s2.dailyTarget, 45);
    expect(s2.pageMode, ReaderPageMode.scroll);
    expect(s2.themeAuto, isTrue);
    expect(s2.customFontFamily, 'MyFont');
    expect(s2.autoBackupIntervalDays, 7);
  });

  test('ThemeScheduler resolves by hour', () {
    expect(ThemeScheduler.modeForHour(10), ReaderThemeMode.light);
    expect(ThemeScheduler.modeForHour(20), ReaderThemeMode.sepia);
    expect(ThemeScheduler.modeForHour(1), ReaderThemeMode.dark);
    expect(ThemeScheduler.modeForHour(23), ReaderThemeMode.dark);
  });

  test('TextParser chapter splitting keeps offsets in bounds', () async {
    final content = '第一章\n正文开头文字。\n第二章\n第二段正文。\n第三章\n结尾。';
    final bytes = Uint8List.fromList(utf8.encode(content));
    final parsed = await TextParser.parseBytes(bytes);
    expect(parsed.chapters.length, greaterThanOrEqualTo(3));
    for (final c in parsed.chapters) {
      expect(c.start, inInclusiveRange(0, content.length));
      expect(c.end, inInclusiveRange(c.start, content.length));
    }
    // 章节拼接后应还原出正文
    final joined = parsed.chapters.map((c) => content.substring(c.start, c.end)).join();
    expect(joined, contains('正文开头文字'));
    expect(joined, contains('第二段正文'));
    expect(joined, contains('结尾'));
  });

  test('TextParser detects chapter titles without space (第1章xxx)', () {
    final content = '开篇内容\n第1章七星鲁王血屍\n这是第一章正文。\n第2章 测试\n第二章正文。';
    final chapters = TextParser.splitChapters(content);
    final titles = chapters.map((c) => c.title).toList();
    expect(titles, contains('第1章七星鲁王血屍'));
    expect(titles, contains('第2章 测试'));
    expect(chapters.length, 3); // 开篇 + 两章
  });

  test('TextParser splits huge chapters to avoid render freeze', () {
    final big = '第1章${'测试正文内容。' * 20000}'; // > 50k 字符
    final chapters = TextParser.splitChapters(big);
    expect(chapters.length, greaterThan(1));
    for (final c in chapters) {
      expect(c.end - c.start, lessThanOrEqualTo(50000 + 5000));
    }
    // 拼接后内容应完整还原
    final joined = chapters.map((c) => big.substring(c.start, c.end)).join();
    expect(joined, big);
  });
}
