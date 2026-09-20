import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'open_document_archive_parser.dart';

/// LibreOffice/OpenDocument Text (.odt) reader.
///
/// ODT is a ZIP package. The actual document body is stored in content.xml.
/// We intentionally convert it to plain text so the existing reader, search,
/// bookmarks and offline TTS can reuse the same pipeline as TXT/HTML.
class OdtParser {
  static Future<String> parse(Uint8List bytes) async {
    final archive = OpenDocumentArchiveParser.decode(bytes);
    final xml = OpenDocumentArchiveParser.readXml(archive, 'content.xml');

    final document = XmlDocument.parse(xml);
    final paragraphs = OpenDocumentArchiveParser.paragraphs(
      document,
      {'p', 'h'},
    );

    if (paragraphs.isEmpty) {
      throw const FormatException('ODT 文档中没有可读取的正文内容');
    }
    return OpenDocumentArchiveParser.joinParagraphs(paragraphs);
  }
}
