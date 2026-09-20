class FormatDetector {
  static const Set<String> textExts = {
    'txt', 'epub', 'mobi', 'azw3', 'html', 'htm', 'md', 'markdown', 'fb2', 'odt', 'docx',
  };
  static const Set<String> audioExts = {
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'm4b', 'amr',
  };

  static String? detectFormat(String path) {
    final parts = path.split('.');
    if (parts.length < 2) return null;
    final ext = parts.last.toLowerCase();
    if (textExts.contains(ext)) {
      if (ext == 'markdown') return 'md';
      if (ext == 'htm') return 'html';
      return ext;
    }
    if (audioExts.contains(ext)) return ext;
    return null;
  }
}
