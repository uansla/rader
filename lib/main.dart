import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'services/windows_context_menu_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows && args.contains('--install-context-menu')) {
    exit(await WindowsContextMenuService.install() ? 0 : 1);
  }
  if (Platform.isWindows && args.contains('--uninstall-context-menu')) {
    exit(await WindowsContextMenuService.uninstall() ? 0 : 1);
  }

  runApp(ReaderApp(initialArguments: args));
}
