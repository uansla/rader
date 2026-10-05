import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'core/app_theme.dart';
import 'ui/home_screen.dart';

class ReaderApp extends StatelessWidget {
  final List<String> initialArguments;

  const ReaderApp({
    super.key,
    this.initialArguments=const [],
  });

  @override
  Widget build(BuildContext context) {
    final initialOpenPaths=initialArguments
        .where((arg)=>!arg.startsWith('--'))
        .where((arg)=>arg.trim().isNotEmpty)
        .toList(growable:false);

    return ChangeNotifierProvider(
      create: (_)=>AppState()..init(),
      child: Consumer<AppState>(
        builder:(context,state,_) {
          final dark=state.settings.followSystemDark
              ? MediaQuery.of(context).platformBrightness==Brightness.dark
              : false;
          return MaterialApp(
            title:'Reader',
            debugShowCheckedModeBanner:false,
            theme:buildAppTheme(Brightness.light),
            darkTheme:buildAppTheme(Brightness.dark),
            themeMode:dark ? ThemeMode.dark : ThemeMode.light,
            home:HomeScreen(initialOpenPaths: initialOpenPaths),
          );
        },
      ),
    );
  }
}
