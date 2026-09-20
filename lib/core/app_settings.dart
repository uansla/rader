import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum ReaderThemeMode { light, dark, sepia }

/// 书架视图模式：网格 / 列表
enum ShelfViewMode { grid, list }

/// 阅读器翻页方式：横滑分章 / 整本连续滚动
enum ReaderPageMode { paged, scroll }

class ReaderSettings {
  double fontSize;
  double lineHeight;
  String fontFamily;
  ReaderThemeMode themeMode;
  double ttsRate;
  bool followSystemDark;
  bool themeAuto;
  int dailyTarget;
  ShelfViewMode shelfMode;
  ReaderPageMode pageMode;
  int autoBackupIntervalDays;
  String customFontFamily;

  ReaderSettings({
    this.fontSize = 18,
    this.lineHeight = 1.8,
    this.fontFamily = '',
    this.themeMode = ReaderThemeMode.light,
    this.ttsRate = 0.5,
    this.followSystemDark = true,
    this.themeAuto = false,
    this.dailyTarget = 30,
    this.shelfMode = ShelfViewMode.grid,
    this.pageMode = ReaderPageMode.paged,
    this.autoBackupIntervalDays = 0,
    this.customFontFamily = '',
  });

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
    ReaderThemeMode? themeMode,
    double? ttsRate,
    bool? followSystemDark,
    bool? themeAuto,
    int? dailyTarget,
    ShelfViewMode? shelfMode,
    ReaderPageMode? pageMode,
    int? autoBackupIntervalDays,
    String? customFontFamily,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      themeMode: themeMode ?? this.themeMode,
      ttsRate: ttsRate ?? this.ttsRate,
      followSystemDark: followSystemDark ?? this.followSystemDark,
      themeAuto: themeAuto ?? this.themeAuto,
      dailyTarget: dailyTarget ?? this.dailyTarget,
      shelfMode: shelfMode ?? this.shelfMode,
      pageMode: pageMode ?? this.pageMode,
      autoBackupIntervalDays:
          autoBackupIntervalDays ?? this.autoBackupIntervalDays,
      customFontFamily: customFontFamily ?? this.customFontFamily,
    );
  }
}

class SettingsManager {
  static const _kFontSize = 'reader.fontSize';
  static const _kLineHeight = 'reader.lineHeight';
  static const _kFontFamily = 'reader.fontFamily';
  static const _kThemeMode = 'reader.themeMode';
  static const _kTtsRate = 'reader.ttsRate';
  static const _kFollowSystemDark = 'reader.followSystemDark';
  static const _kThemeAuto = 'reader.themeAuto';
  static const _kDailyTarget = 'reader.dailyTarget';
  static const _kShelfMode = 'reader.shelfMode';
  static const _kPageMode = 'reader.pageMode';
  static const _kAutoBackup = 'reader.autoBackupIntervalDays';
  static const _kCustomFont = 'reader.customFontFamily';

  Future<ReaderSettings> load() async {
    final sp = await SharedPreferences.getInstance();
    return ReaderSettings(
      fontSize: sp.getDouble(_kFontSize) ?? 18,
      lineHeight: sp.getDouble(_kLineHeight) ?? 1.8,
      fontFamily: sp.getString(_kFontFamily) ?? '',
      themeMode: ReaderThemeMode.values[
          sp.getInt(_kThemeMode) ?? ReaderThemeMode.light.index],
      ttsRate: sp.getDouble(_kTtsRate) ?? 0.5,
      followSystemDark: sp.getBool(_kFollowSystemDark) ?? true,
      themeAuto: sp.getBool(_kThemeAuto) ?? false,
      dailyTarget: sp.getInt(_kDailyTarget) ?? 30,
      shelfMode: ShelfViewMode.values[
          sp.getInt(_kShelfMode) ?? ShelfViewMode.grid.index],
      pageMode: ReaderPageMode.values[
          sp.getInt(_kPageMode) ?? ReaderPageMode.paged.index],
      autoBackupIntervalDays: sp.getInt(_kAutoBackup) ?? 0,
      customFontFamily: sp.getString(_kCustomFont) ?? '',
    );
  }

  Future<void> save(ReaderSettings s) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kFontSize, s.fontSize);
    await sp.setDouble(_kLineHeight, s.lineHeight);
    await sp.setString(_kFontFamily, s.fontFamily);
    await sp.setInt(_kThemeMode, s.themeMode.index);
    await sp.setDouble(_kTtsRate, s.ttsRate);
    await sp.setBool(_kFollowSystemDark, s.followSystemDark);
    await sp.setBool(_kThemeAuto, s.themeAuto);
    await sp.setInt(_kDailyTarget, s.dailyTarget);
    await sp.setInt(_kShelfMode, s.shelfMode.index);
    await sp.setInt(_kPageMode, s.pageMode.index);
    await sp.setInt(_kAutoBackup, s.autoBackupIntervalDays);
    await sp.setString(_kCustomFont, s.customFontFamily);
  }
}

Map<String, Object?> decodeJsonOrEmpty(String? s) {
  if (s == null || s.isEmpty) return {};
  try {
    return json.decode(s) as Map<String, Object?>;
  } catch (_) {
    return {};
  }
}
