import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';

class ChapterSpan {
  final String title;
  final int start;
  final int end;
  ChapterSpan(this.title, this.start, this.end);
}

class ParsedText {
  final String content;
  final String encoding;
  final List<ChapterSpan> chapters;
  ParsedText(this.content, this.encoding, this.chapters);
}

class TextParser {
  static final List<RegExp> _titlePatterns = [
    RegExp(r'^第\s*[0-9０-９〇一二三四五六七八九十百千万零两]{1,10}\s*[章回节卷部篇集话讲](?:\s*[^。！？]{1,40})?$'),
    RegExp(r'^[Cc][Hh][Aa][Pp][Tt][Ee][Rr]\s+\d+'),
    RegExp(r'^(?:序章|楔子|序言|前言|引言|引子|尾声|后记|结语|终章|最终章|大结局|完结篇|番外|番外篇)(?:[：:\s].*)?$'),
    RegExp(r'^卷\s*[一二三四五六七八九十百零两]+\s*[：: ]'),
  ];

  static String detectEncoding(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return 'utf-8';
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return 'utf-16le';
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return 'utf-16be';
    }
    final sample = bytes.length > 2000 ? bytes.sublist(0, 2000) : bytes;
    // 去掉末尾可能被截断的 UTF-8 多字节字符，再校验，避免误判为 GBK
    var end = sample.length;
    while (end > 0) {
      final b = sample[end - 1];
      if (b < 0x80 || b >= 0xC0) break; // ASCII 或字符起始字节
      end--;
    }
    try {
      utf8.decode(sample.sublist(0, end));
      return 'utf-8';
    } catch (_) {}
    return 'gbk';
  }

  static Future<String> decode(Uint8List bytes) async {
    final enc = detectEncoding(bytes);
    switch (enc) {
      case 'utf-16le':
        return _decodeUtf16(bytes, 2);
      case 'utf-16be':
        return _decodeUtf16(bytes, 2, bigEndian: true);
      default:
        try {
          return utf8.decode(bytes);
        } catch (_) {
          try {
            // 用 gb18030（GBK 超集）：Windows 端的 charset_converter
            // 映射表只认 gb2312/gb18030，不认 gbk，传 gbk 会报 charset_name_unrecognized
            // 导致乱码。gb18030 在 Windows 和 Android 上都可用。
            return await CharsetConverter.decode('gb18030', bytes);
          } catch (_) {
            try {
              return await CharsetConverter.decode('gb2312', bytes);
            } catch (_) {
              return utf8.decode(bytes, allowMalformed: true);
            }
          }
        }
    }
  }

  static String _decodeUtf16(Uint8List bytes, int skip, {bool bigEndian = false}) {
    final codeUnits = <int>[];
    for (var i = skip; i + 1 < bytes.length; i += 2) {
      final lo = bytes[i];
      final hi = bytes[i + 1];
      codeUnits.add(bigEndian ? (hi << 8) | lo : (lo | (hi << 8)));
    }
    return String.fromCharCodes(codeUnits);
  }

  static const int _maxChapterChars = 50000;

  static List<ChapterSpan> splitChapters(String content) {
    final chapters = <ChapterSpan>[];
    final lines = content.split('\n');
    var cursor = 0;
    var currentStart = 0;
    var currentTitle = '开篇';
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      final isLast = i == lines.length - 1;
      if (trimmed.length <= 60 && _isChapterTitle(trimmed)) {
        if (cursor > currentStart) {
          chapters.add(ChapterSpan(currentTitle, currentStart, cursor));
        }
        currentStart = cursor;
        currentTitle = _cleanTitle(trimmed);
      }
      cursor = isLast ? cursor + line.length : cursor + line.length + 1;
    }
    if (cursor > currentStart) {
      chapters.add(ChapterSpan(currentTitle, currentStart, cursor));
    }
    final len = content.length;
    final result = <ChapterSpan>[];
    for (final c in chapters) {
      final start = c.start.clamp(0, len);
      final end = c.end.clamp(0, len);
      final spanLen = end - start;
      if (spanLen <= _maxChapterChars) {
        result.add(ChapterSpan(c.title, start, end));
      } else {
        // 超大章节（标题未被识别等情况）按固定大小切分，
        // 避免单个几十万字的段落渲染卡死。
        var s = start;
        while (s < end) {
          var e = (s + _maxChapterChars).clamp(0, end);
          if (e <= s) e = s + 1; // 保证前进
          if (e < end) {
            // 尽量在换行处断开（包含换行符，保持逐行完整与拼接无间隙）
            final nl = content.indexOf('\n', e);
            if (nl != -1 && nl < e + 5000) {
              e = nl + 1;
            }
          }
          result.add(ChapterSpan(c.title, s, e));
          s = e;
        }
      }
    }
    return result;
  }

  static bool _isChapterTitle(String line) {
    for (final p in _titlePatterns) {
      if (p.hasMatch(line)) return true;
    }
    return false;
  }

  static String _cleanTitle(String t) {
    var s = t.trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    if (s.length > 60) s = s.substring(0, 60);
    return s;
  }

  static Future<ParsedText> parseBytes(Uint8List bytes) async {
    final content = await decode(bytes);
    final enc = detectEncoding(bytes);
    final chapters = splitChapters(content);
    return ParsedText(content, enc, chapters);
  }

  static String stripHtml(String html) {
    var s = html.replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'</div>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = s.replaceAll('&nbsp;', ' ');
    s = s.replaceAll('&amp;', '&');
    s = s.replaceAll('&lt;', '<');
    s = s.replaceAll('&gt;', '>');
    s = s.replaceAll('&quot;', '"');
    return s;
  }
}
