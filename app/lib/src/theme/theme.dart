import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// CyberDog's light theme: white and silver surfaces with one blue accent.
ThemeData nightdropTheme() {
  // The palette of the site: near-white surfaces, ink text, a blue-to-cyan accent, nothing warm.
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1F6FFF),
    brightness: Brightness.light,
  ).copyWith(
    primary: const Color(0xFF1F6FFF),
    onPrimary: const Color(0xFFFFFFFF),
    primaryContainer: const Color(0xFFE3EEFF),
    onPrimaryContainer: const Color(0xFF0B2A66),
    secondary: const Color(0xFF1F7BFF),
    onSecondary: const Color(0xFFFFFFFF),
    secondaryContainer: const Color(0xFFE8F1FF),
    onSecondaryContainer: const Color(0xFF0B111D),
    tertiary: const Color(0xFF19B8F2),
    onTertiary: const Color(0xFFFFFFFF),
    surface: const Color(0xFFF6F8FC),
    onSurface: const Color(0xFF0B111D),
    onSurfaceVariant: const Color(0xFF5C697D),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    surfaceContainerLow: const Color(0xFFFBFCFE),
    surfaceContainer: const Color(0xFFFFFFFF),
    surfaceContainerHigh: const Color(0xFFFFFFFF),
    surfaceContainerHighest: const Color(0xFFFFFFFF),
    outline: const Color(0xFF8E99AA),
    outlineVariant: const Color(0xFFDCE4EF),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Screens are see-through: the light backdrop painted behind the whole app shows under them
    // (see AppBackdrop, installed by the MaterialApp builder).
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
      // Dark status-bar icons over the light backdrop.
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    // Render color emoji on Linux, which may have no emoji font, so emoji would otherwise appear
    // as missing-glyph boxes. Not on Windows: the bundled font is COLRv1, which Flutter's
    // DirectWrite path there draws as nothing (every emoji was blank), while the system's
    // Segoe UI Emoji is found by the normal fallback.
    fontFamilyFallback: defaultTargetPlatform == TargetPlatform.windows
        ? null
        : const ['NotoColorEmoji'],
  );
}
