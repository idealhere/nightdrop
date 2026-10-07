import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Night Dog's dark, low-key theme.
ThemeData nightdropTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF7C83FD),
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Screens are see-through: the night forest painted behind the whole app shows under them
    // (see NightForestBackground, installed by the MaterialApp builder).
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(centerTitle: true),
    // Render color emoji on Linux, which may have no emoji font, so emoji would otherwise appear
    // as missing-glyph boxes. Not on Windows: the bundled font is COLRv1, which Flutter's
    // DirectWrite path there draws as nothing (every emoji was blank), while the system's
    // Segoe UI Emoji is found by the normal fallback.
    fontFamilyFallback: defaultTargetPlatform == TargetPlatform.windows
        ? null
        : const ['NotoColorEmoji'],
  );
}
