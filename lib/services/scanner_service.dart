import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/repositories.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import 'format_detector.dart';

class ScanSummary {
  int added = 0;
  int updated = 0;
  int skipped = 0;
  int textBooks = 0;
  int audioBooks = 0;
}

class ScannerService {
  final BookRepository _books;
  final ChapterRepository _chapters;

  ScannerService(this._books, this._chapters);

  static const _skipDirs = {
    'build', 'out', 'bin', 'obj', 'dist', 'target',
    '.git', '.dart_tool', '.gradle', '.idea', '.vs', '.vscode', '.cache',
    'node_modules', '.svn', '.hg', '__pycache__', '.pub-cache',
    '.metadata', '.plugins',
  };

  static const _junkBasenames = {
    'readme', 'readme.md', 'readme.txt', 'readme.txt.txt',
    'changelog', 'changelog.md', 'license', 'license.txt', 'copying',
    'cmakelists', 'cmakelists.txt', 'cmakecache', 'cmakecache.txt',
    'cmake_install.cmake', 'install_manifest', 'stderr', 'stdout',
    'package.json', 'package-lock.json', 'pubspec.yaml', 'pubspec.lock',
    'r', 'r.txt', 'r-def', 'stableids', 'output-metadata.json',
    'output.json', 'file-map', 'redirect', 'dex-renamer-state',
    'manifest-merger-debug-report', 'native-libs-blame-debug-report',
    'nestedresourcesvalidationreport', 'package-aware-r',
    'version.json', '.gitignore', '.gitattributes',
  };

  bool _isJunkPath(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    for (final part in parts) {
      if (_skipDirs.contains(part.toLowerCase())) return true;
    }
    final base = parts.isEmpty ? '' : parts.last.toLowerCase();
    if (_junkBasenames.contains(base)) return true;
    return false;
  }

  Future<ScanSummary> scanDirectories(List<String> dirs) async {
    final summary = ScanSummary();
    final audioByDir = <String, List<File>>{};

    await _cleanupMissing();

    for (final dir in dirs) {
      if (!Directory(dir).existsSync()) continue;
      try {
        await for (final entity
            in Directory(dir).list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          if (_isJunkPath(entity.path)) continue;
          final fmt = FormatDetector.detectFormat(entity.path);
          if (fmt == null) continue;
          if (_isTextFormat(fmt)) {
            await _upsertTextBook(entity, fmt, summary);
          } else {
            audioByDir.putIfAbsent(entity.parent.path, () => []).add(entity);
          }
        }
      } catch (_) {
        summary.skipped++;
      }
    }

    for (final entry in audioByDir.entries) {
      await _upsertAudioBook(entry.value, summary);
    }
    return summary;
  }

  Future<void> _cleanupMissing() async {
    final all = await _books.getAll();
    for (final b in all) {
      final type = FileSystemEntity.typeSync(b.path);
      if (type == FileSystemEntityType.notFound) {
        await _books.delete(b.id!);
      }
    }
  }

  bool _isTextFormat(String fmt) {
    return const {
      'txt', 'epub', 'mobi', 'azw3', 'html', 'md', 'fb2', 'odt', 'docx'
    }.contains(fmt);
  }

  Future<void> _upsertTextBook(File file, String fmt, ScanSummary s) async {
    final size = await file.length();
    if (size < 1024) {
      s.skipped++;
      return;
    }
    final existing = await _books.getByPath(file.path);
    if (existing != null) {
      if (existing.fileSize != size) {
        await _books.update(existing.copyWith(fileSize: size));
        s.updated++;
      } else {
        s.skipped++;
      }
      return;
    }
    final book = Book(
      title: _bookTitleFromPath(file.path),
      format: fmt,
      type: 'text',
      path: file.path,
      fileSize: size,
      addedAt: DateTime.now(),
    );
    await _books.insert(book);
    s.added++;
    s.textBooks++;
  }

  Future<void> _upsertAudioBook(List<File> files, ScanSummary s) async {
    files.sort((a, b) => a.path.compareTo(b.path));
    final first = files.first;
    final isMulti = files.length > 1;
    final dirPath = first.parent.path;
    final title = isMulti
        ? p.basename(dirPath)
        : p.basenameWithoutExtension(first.path);
    final existing = await _books.getByPath(isMulti ? dirPath : first.path);
    if (existing != null) {
      s.skipped++;
      return;
    }
    final totalSize = files.fold<int>(0, (sum, f) => sum + (f.lengthSync()));
    final book = Book(
      title: title,
      format: files.length == 1 ? FormatDetector.detectFormat(first.path)! : 'm4a',
      type: 'audio',
      path: isMulti ? dirPath : first.path,
      fileSize: totalSize,
      totalChapters: files.length,
      addedAt: DateTime.now(),
    );
    final id = await _books.insert(book);
    final chapters = <Chapter>[];
    for (var i = 0; i < files.length; i++) {
      chapters.add(Chapter(
        bookId: id,
        idx: i,
        title: p.basenameWithoutExtension(files[i].path),
        filePath: files[i].path,
      ));
    }
    await _chapters.replaceForBook(id, chapters);
    s.added++;
    s.audioBooks++;
  }
}

// Avoid circular import; inline helper.
String _bookTitleFromPath(String path) {
  return p.basenameWithoutExtension(path);
}
