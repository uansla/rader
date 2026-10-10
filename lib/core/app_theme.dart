import 'package:flutter/material.dart';

class ReaderPalette {
  final Color background;
  final Color text;
  final Color subtle;
  final Color accent;
  final Color toolbar;
  final Color toolbarText;
  final Color divider;
  final Brightness brightness;

  const ReaderPalette({
    required this.background,
    required this.text,
    required this.subtle,
    required this.accent,
    required this.toolbar,
    required this.toolbarText,
    required this.divider,
    required this.brightness,
  });

  static const light = ReaderPalette(
    background: Color(0xFFF7F3E8),
    text: Color(0xFF2B2B2B),
    subtle: Color(0xFF8A8578),
    accent: Color(0xFF6B8E23),
    toolbar: Color(0xFFFDFBF4),
    toolbarText: Color(0xFF3A3A3A),
    divider: Color(0xFFE3DDCC),
    brightness: Brightness.light,
  );

  static const sepia = ReaderPalette(
    background: Color(0xFFEAE0C8),
    text: Color(0xFF3D3222),
    subtle: Color(0xFF9A8B6F),
    accent: Color(0xFF8B5E3C),
    toolbar: Color(0xFFF3ECD8),
    toolbarText: Color(0xFF4A3D28),
    divider: Color(0xFFD6C9AB),
    brightness: Brightness.light,
  );

  static const dark = ReaderPalette(
    background: Color(0xFF1E1E1E),
    text: Color(0xFFC9C9C9),
    subtle: Color(0xFF777777),
    accent: Color(0xFF8FBC5F),
    toolbar: Color(0xFF262626),
    toolbarText: Color(0xFFDDDDDD),
    divider: Color(0xFF3A3A3A),
    brightness: Brightness.dark,
  );
}

ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6B8E23),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
