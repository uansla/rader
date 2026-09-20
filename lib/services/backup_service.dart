import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_database.dart';

/// 自动备份：按设定的间隔（天）静默备份数据库到 backups/ 目录。
/// 每天只检查一次（记录上次检查时间）。
class BackupService {
  static const _kLastCheck = 'reader.backupLastCheck';
  static const _kLastBackup = 'reader.backupLastBackup';

  /// 根据设置的天数决定是否需要备份；需要则执行。
  /// [intervalDays] 0 表示关闭自动备份。
  static Future<String?> maybeBackup(int intervalDays) async {
    if (intervalDays <= 0) return null;
    final sp = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastCheck = DateTime.fromMillisecondsSinceEpoch(
        sp.getInt(_kLastCheck) ?? 0);
    // 每天最多检查一次
    if (_isSameDay(lastCheck, now)) return null;
    await sp.setInt(_kLastCheck, now.millisecondsSinceEpoch);

    final lastBackup = DateTime.fromMillisecondsSinceEpoch(
        sp.getInt(_kLastBackup) ?? 0);
    if (now.difference(lastBackup).inDays < intervalDays) return null;

    final path = await backupNow();
    if (path != null) {
      await sp.setInt(_kLastBackup, now.millisecondsSinceEpoch);
    }
    return path;
  }

  /// 立即备份，返回备份文件路径（失败返回 null）。
  static Future<String?> backupNow() async {
    final dbPath = AppDatabase.dbPath;
    if (dbPath == null) return null;
    if (!File(dbPath).existsSync()) return null;
    final dir = await getApplicationSupportDirectory();
    final backupDir = Directory(p.join(dir.path, 'backups'));
    if (!backupDir.existsSync()) backupDir.createSync(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dest = p.join(backupDir.path, 'reader_backup_$stamp.db');
    try {
      await File(dbPath).copy(dest);
      return dest;
    } catch (_) {
      return null;
    }
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
