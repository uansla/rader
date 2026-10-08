import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 仅记录未处理异常/闪退，不记录普通运行信息。
///
/// Windows:
///   %LOCALAPPDATA%\Reader\Reader-Crash.log
///
/// 记录内容只包含时间、错误来源、异常文本和堆栈，不记录书名、文档正文、
/// 阅读进度或其他正常运行数据。
class CrashLogService {
  static bool _installed = false;
  static String? _logPath;
  static final Set<String> _recentKeys = <String>{};

  static String get logPath => _logPath ?? _fallbackPath();

  static Future<void> install() async {
    if (_installed) return;
    _installed = true;
    _logPath = _fallbackPath();
    try {
      await File(logPath).parent.create(recursive: true);
    } catch (_) {}

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      _record(
        source: 'FlutterError',
        error: details.exception,
        stack: details.stack,
      );
      previousFlutterError?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _record(
        source: 'PlatformDispatcher',
        error: error,
        stack: stack,
      );
      return false;
    };
  }

  static Future<void> recordUnhandled(Object error, StackTrace stack) {
    return _record(source: 'Zone', error: error, stack: stack);
  }

  /// 记录明确发生的错误，但不记录普通运行状态。
  static Future<void> recordError({
    required String source,
    required Object error,
    StackTrace? stack,
  }) {
    return _record(
      source: source,
      error: error,
      stack: stack ?? StackTrace.current,
    );
  }

  static bool get hasLogFile => File(logPath).existsSync();

  /// 在 Windows 文件资源管理器中打开错误日志所在目录。
  static Future<bool> openLogFolder() async {
    try {
      final dir = File(logPath).parent;
      await dir.create(recursive: true);
      if (Platform.isWindows) {
        final process = await Process.start(
          'explorer.exe',
          <String>[dir.path],
          mode: ProcessStartMode.detached,
        );
        return process.pid > 0;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> selfTest() {
    return _record(
      source: 'SelfTest',
      error: StateError('Crash log self-test'),
      stack: StackTrace.current,
    );
  }

  static Future<void> _record({
    required String source,
    required Object? error,
    required StackTrace? stack,
  }) async {
    final text = error?.toString() ?? '<unknown error>';
    final stackText = stack?.toString() ?? '<no stack trace>';
    final key = '$text\n$stackText';
    if (!_recentKeys.add(key)) return;
    if (_recentKeys.length > 32) {
      _recentKeys.remove(_recentKeys.first);
    }

    final line = StringBuffer()
      ..writeln('===== Reader 未处理错误 =====')
      ..writeln('时间: ${DateTime.now().toIso8601String()}')
      ..writeln('来源: $source')
      ..writeln('错误: $text')
      ..writeln('堆栈:')
      ..writeln(stackText)
      ..writeln();

    try {
      final file = File(logPath);
      await file.parent.create(recursive: true);

      // 只保留一个错误日志文件；异常积累过大时重新开始记录。
      if (await file.exists() && await file.length() > 5 * 1024 * 1024) {
        await file.writeAsString('');
      }

      await file.writeAsString(
        line.toString(),
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Logging must never become another source of crashes.
    }
  }

  static String _fallbackPath() {
    if (Platform.isWindows) {
      final base = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          Directory.systemTemp.path;
      return p.join(base, 'Reader', 'Reader-Crash.log');
    }

    final base = Platform.environment['XDG_STATE_HOME'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return p.join(base, '.reader', 'Reader-Crash.log');
  }
}
