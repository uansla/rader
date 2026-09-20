import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class OpenDocumentArchiveParser {
  static String _readXml(Archive archive, String name) {
    ArchiveFile? file;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final normalized = entry.name.replaceAll('\\', '/');
      if (normalized == name) {
        file = entry;
        break;
      }
    }
    if (file == null) {
      throw FormatException('文档内部缺少 $name');
    }
    return utf8.decode(file.readBytes(), allowMalformed: true);
  }

  static Archive decode(Uint8List bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('无法读取文档压缩包：$e');
    }
  }

  static String extractParagraphText(XmlElement element) {
    final buffer = StringBuffer();

    void visit(XmlNode node) {
      if (node is XmlText) {
        buffer.write(node.value);
        return;
      }
      if (node is! XmlElement) return;

      final local = node.name.local;
      if (local == 'br' || local == 'line-break') {
        buffer.write('\n');
        return;
      }
      if (local == 'tab') {
        buffer.write('\t');
        return;
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(element);
    return buffer.toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }

  static List<String> paragraphs(XmlDocument document, Set<String> names) {
    final result = <String>[];
    for (final element in document.descendantElements) {
      if (!names.contains(element.name.local)) continue;
      final text = extractParagraphText(element);
      if (text.isNotEmpty) result.add(text);
    }
    return result;
  }

  static String joinParagraphs(List<String> paragraphs) {
    return paragraphs.join('\n\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static String readXml(Archive archive, String name) => _readXml(archive, name);
}
