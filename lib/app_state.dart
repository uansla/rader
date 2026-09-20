import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'core/app_settings.dart';
import 'data/app_database.dart';
import 'data/repositories.dart';
import 'models/book.dart';
import 'models/library_folder.dart';
import 'services/audio_playback_service.dart';
import 'services/backup_service.dart';
import 'services/font_manager.dart';
import 'services/scanner_service.dart';
import 'services/sync_service.dart';
import 'services/text_content_service.dart';
import 'services/tts_service.dart';

class AppState extends ChangeNotifier {
  final bookRepo = BookRepository();
  final chapterRepo = ChapterRepository();
  final bookmarkRepo = BookmarkRepository();
  final noteRepo = NoteRepository();
  final folderRepo = FolderRepository();
  final historyRepo = HistoryRepository();
  final readDailyRepo = ReadDailyRepository();
  final audio = AudioPlaybackService();
  final tts = TtsService();

  late TextContentService textContent;
  late ScannerService scanner;
  late SyncService syncService;
  late MarkdownExporter markdownExporter;
  final SettingsManager settingsManager = SettingsManager();

  List<Book> books = [];
  List<LibraryFolder> folders = [];
  ReaderSettings settings = ReaderSettings();
  bool scanning = false;
  bool initialized = false;
  String? lastScanMessage;

  Future<void> init() async {
    if (initialized) return;
    textContent = TextContentService(chapterRepo);
    scanner = ScannerService(bookRepo, chapterRepo);
    syncService = SyncService(
        books: bookRepo, bookmarks: bookmarkRepo, notes: noteRepo);
    markdownExporter =
        MarkdownExporter(books: bookRepo, bookmarks: bookmarkRepo, notes: noteRepo);
    settings = await settingsManager.load();
    books = await bookRepo.getAll();
    folders = await folderRepo.getAll();
    if (folders.isEmpty) {
      await _addDefaultFolders();
      folders = await folderRepo.getAll();
    }
    initialized = true;
    notifyListeners();
    scan();
    // 启动钩子：重载自定义字体 + 自动备份
    if (settings.customFontFamily.isNotEmpty) {
      await FontManager.reloadSaved(settings.customFontFamily);
    }
    if (settings.autoBackupIntervalDays > 0) {
      await BackupService.maybeBackup(settings.autoBackupIntervalDays);
    }
  }

  Future<Directory> getBooksDirectory() async {
    final dir = await getApplicationSupportDirectory();
    final booksDir = Directory(p.join(dir.path, 'books'));
    if (!booksDir.existsSync()) booksDir.createSync(recursive: true);
    return booksDir;
  }

  Future<void> _addDefaultFolders() async {
    final candidates = <String>[];
    if (Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      if (profile != null) {
        candidates.add(p.join(profile, 'Documents'));
      }
    } else if (Platform.isAndroid) {
      candidates.add('/storage/emulated/0/Download');
      candidates.add('/storage/emulated/0/Documents');
      candidates.add('/storage/emulated/0/Books');
    }
    for (final c in candidates) {
      if (Directory(c).existsSync()) {
        await folderRepo.add(c);
      }
    }
    final booksDir = await getBooksDirectory();
    await folderRepo.add(booksDir.path);
  }

  Future<void> scan({List<String>? dirs}) async {
    if (scanning) return;
    scanning = true;
    notifyListeners();
    final paths = dirs ?? [
      ...folders.where((f) => f.enabled).map((f) => f.path),
    ];
    try {
      final summary = await scanner.scanDirectories(paths);
      lastScanMessage =
          '扫描完成：新增 ${summary.added}，更新 ${summary.updated}，跳过 ${summary.skipped}';
    } catch (e) {
      lastScanMessage = '扫描出错：$e';
    }
    scanning = false;
    books = await bookRepo.getAll();
    notifyListeners();
  }

  Future<void> addFolder(String path) async {
    await folderRepo.add(path);
    folders = await folderRepo.getAll();
    notifyListeners();
    await scan(dirs: [path]);
  }

  Future<void> removeFolder(int id) async {
    await folderRepo.remove(id);
    folders = await folderRepo.getAll();
    notifyListeners();
  }

  Future<void> toggleFavorite(Book b) async {
    final fav = !b.isFavorite;
    await bookRepo.setFavorite(b.id!, fav);
    books = await bookRepo.getAll();
    notifyListeners();
  }

  Future<void> updateProgress(Book b,
      {int? chapterIdx, int? position, double? progress}) async {
    await bookRepo.touch(b.id!,
        chapterIdx: chapterIdx,
        position: position,
        progress: progress ?? b.progress);
    books = await bookRepo.getAll();
    notifyListeners();
  }

  Future<void> recordHistory(int bookId,
      {String action = 'read', int chapterIdx = 0, int position = 0}) async {
    await historyRepo.add(bookId,
        action: action, chapterIdx: chapterIdx, position: position);
  }

  Future<void> deleteBook(Book b) async {
    await bookRepo.delete(b.id!);
    books = await bookRepo.getAll();
    notifyListeners();
  }

  Future<void> updateSettings(ReaderSettings s) async {
    settings = s;
    await settingsManager.save(s);
    notifyListeners();
  }

  Future<BookSession> openBook(Book book) async {
    await recordHistory(book.id!);
    return textContent.open(book);
  }

  /// 今日已读分钟数 + 连续打卡天数（供书架顶部展示）。
  Future<(int, int)> todayMinutesAndStreak() async {
    final today = await readDailyRepo.minutesOn(DateTime.now());
    final streak = await readDailyRepo.streak();
    return (today, streak);
  }

  Future<String> backupDatabase() async {
    final dbPath = AppDatabase.dbPath;
    if (dbPath == null) return '备份失败：数据库未初始化';
    if (!File(dbPath).existsSync()) return '备份失败：未找到数据库';
    final dir = await getApplicationSupportDirectory();
    final backupDir = Directory(p.join(dir.path, 'backups'));
    if (!backupDir.existsSync()) backupDir.createSync(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dest = p.join(backupDir.path, 'reader_backup_$stamp.db');
    await File(dbPath).copy(dest);
    return '备份完成：$dest';
  }

  Future<String> restoreDatabase() async {
    final picked = await _pickFile();
    if (picked == null || picked.isEmpty) return '已取消';
    final src = File(picked);
    if (!src.existsSync()) return '备份文件不存在';
    await AppDatabase.close();
    final dbPath = AppDatabase.dbPath;
    if (dbPath == null) return '恢复失败';
    try {
      await src.copy(dbPath);
    } catch (e) {
      return '恢复失败：$e';
    }
    books = await bookRepo.getAll();
    folders = await folderRepo.getAll();
    notifyListeners();
    return '恢复成功，已重新加载数据';
  }

  Future<String?> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['db'],
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.first.path;
  }

  void disposeAll() {
    audio.dispose();
    tts.dispose();
  }
}
