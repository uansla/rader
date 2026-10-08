import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 只记录未处理异常、未捕获异步异常等错误。
/// 正常启动、阅读、扫描、打开文件等行为不会写入此文件。
class ReaderErrorLogger {
  static bool _installed = false;
  static final Set<String> _recentFingerprints = <String>{};

  static Future<void> install() async {
    if (_installed) return;
    _installed = true;

    FlutterError.onError = (details) {
      unawaited(
        _write(
          'Flutter 未处理异常',
          details.exceptionAsString(),
          details.stack,
        ),
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(_write('Dart 未捕获异常', error, stack));
      return true;
    };
  }

  static Future<void> log(Object error, [StackTrace? stack]) =>
      _write('Reader 明确错误', error, stack);

  static Future<void> _write(
    String type,
    Object error, [
    StackTrace? stack,
  ]) async {
    try {
      final fingerprint =
          '$type|${error.runtimeType}|${error.toString()}';
      if (_recentFingerprints.contains(fingerprint)) return;

      _recentFingerprints.add(fingerprint);
      if (_recentFingerprints.length > 64) {
        _recentFingerprints.remove(_recentFingerprints.first);
      }

      final file = await _logFile();
      if (await file.exists() && await file.length() > 5 * 1024 * 1024) {
        await file.writeAsString(
          '===== Reader 错误日志已自动截断 =====\r\n',
          mode: FileMode.write,
          encoding: utf8,
        );
      }

      final body = StringBuffer()
        ..writeln('===== Reader 错误 =====')
        ..writeln('时间: ${DateTime.now().toIso8601String()}')
        ..writeln('类型: $type')
        ..writeln('异常: ${error.runtimeType}')
        ..writeln('详情: $error');

      if (stack != null && stack.toString().trim().isNotEmpty) {
        body
          ..writeln('堆栈:')
          ..writeln(stack);
      }
      body.writeln();

      await file.writeAsString(
        body.toString(),
        mode: FileMode.append,
        encoding: utf8,
      );
    } catch (_) {
      // 错误日志不能反过来导致 Reader 再次报错。
    }
  }

  static Future<File> _logFile() async {
    String base;
    if (Platform.isWindows) {
      base = Platform.environment['LOCALAPPDATA']?.trim() ?? '';
      if (base.isEmpty) {
        final support = await getApplicationSupportDirectory();
        base = support.path;
      }
    } else {
      final support = await getApplicationSupportDirectory();
      base = support.path;
    }

    final dir = Directory('$base${Platform.pathSeparator}Reader');
    await dir.create(recursive: true);
    return File(
      '${dir.path}${Platform.pathSeparator}Reader-Crash.log',
    );
  }
}
