import '../core/app_settings.dart';

/// 按当前小时自动选择阅读主题：
/// 06-18 日间、18-23 护眼、23-06 夜间。
class ThemeScheduler {
  static ReaderThemeMode modeForHour(int hour) {
    if (hour >= 6 && hour < 18) return ReaderThemeMode.light;
    if (hour >= 18 && hour < 23) return ReaderThemeMode.sepia;
    return ReaderThemeMode.dark;
  }

  static ReaderThemeMode resolve(ReaderSettings settings) {
    if (settings.themeAuto) {
      return modeForHour(DateTime.now().hour);
    }
    return settings.themeMode;
  }
}
