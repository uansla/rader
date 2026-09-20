import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'open_document_archive_parser.dart';

/// Microsoft Word Open XML (.docx) reader.
///
/// DOCX is a ZIP package; the main document body is word/document.xml.
/// Paragraphs and headings are converted to plain text for the existing reader.
class DocxParser {
  static Future<String> parse(Uint8List bytes) async {
    final archive = OpenDocumentArchiveParser.decode(bytes);
    final xml = OpenDocumentArchiveParser.readXml(
      archive,
      'word/document.xml',
    );

    final document = XmlDocument.parse(xml);
    final paragraphs = OpenDocumentArchiveParser.paragraphs(
      document,
      {'p'},
    );

    if (paragraphs.isEmpty) {
      throw const FormatException('DOCX 文档中没有可读取的正文内容');
    }
    return OpenDocumentArchiveParser.joinParagraphs(paragraphs);
  }
}
