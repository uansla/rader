import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app.dart';
import 'services/windows_context_menu_service.dart';
import 'services/matcha_tts.dart';
import 'services/crash_log_service.dart';

void main(List<String> args) {
  // Catch setup/startup errors too, not just errors thrown after runApp().
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await CrashLogService.install();

    if (Platform.isWindows && args.contains('--crash-log-self-test')) {
      await CrashLogService.selfTest();
      exit(File(CrashLogService.logPath).existsSync() ? 0 : 1);
    }

    if (Platform.isWindows && args.contains('--tts-self-test')) {
      final base = File(Platform.resolvedExecutable).parent.path;
      final matchaDir = p.join(base, 'matcha-icefall-zh-baker');
      final tts = MatchaTts();
      try {
        final ok = await tts.init(
          acousticModelPath: p.join(matchaDir, 'model-steps-3.onnx'),
          vocoderPath: p.join(base, 'vocos-22khz-univ.onnx'),
          lexiconPath: p.join(matchaDir, 'lexicon.txt'),
          tokensPath: p.join(matchaDir, 'tokens.txt'),
          ruleFsts: [
            p.join(matchaDir, 'phone.fst'),
            p.join(matchaDir, 'date.fst'),
            p.join(matchaDir, 'number.fst'),
          ].join(','),
          numThreads: 2,
        );
        if (!ok) exit(2);
        exit(await tts.selfTest() ? 0 : 3);
      } catch (_) {
        exit(4);
      } finally {
        tts.dispose();
      }
    }

    if (Platform.isWindows && args.contains('--install-context-menu')) {
      exit(await WindowsContextMenuService.install() ? 0 : 1);
    }
    if (Platform.isWindows && args.contains('--uninstall-context-menu')) {
      exit(await WindowsContextMenuService.uninstall() ? 0 : 1);
    }

    runApp(ReaderApp(initialArguments: args));
  }, (error, stack) {
    unawaited(CrashLogService.recordUnhandled(error, stack));
  });
}
