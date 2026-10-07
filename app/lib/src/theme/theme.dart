import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// CyberDog's dark, low-key theme.
ThemeData nightdropTheme() {
  // CyberDog palette: deep night blue surfaces, a restrained violet accent, nothing warm.
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF9B7CFF),
    brightness: Brightness.dark,
  ).copyWith(
    primary: const Color(0xFF7657FF),
    onPrimary: const Color(0xFFF5F7FF),
    primaryContainer: const Color(0xFF2A2364),
    onPrimaryContainer: const Color(0xFFE6DEFF),
    secondary: const Color(0xFF9B7BFF),
    onSecondary: const Color(0xFF14102B),
    secondaryContainer: const Color(0xFF171A40),
    onSecondaryContainer: const Color(0xFFF5F7FF),
    tertiary: const Color(0xFF9B7BFF),
    onTertiary: const Color(0xFF0B0820),
    surface: const Color(0xFF090D1F),
    onSurface: const Color(0xFFF4F5FA),
    onSurfaceVariant: const Color(0xFFA8AEC5),
    surfaceContainerLowest: const Color(0xFF050816),
    surfaceContainerLow: const Color(0xFF090D1F),
    surfaceContainer: const Color(0xFF0D1225),
    surfaceContainerHigh: const Color(0xFF0F1529),
    surfaceContainerHighest: const Color(0xFF11172C),
    outline: const Color(0xFF707892),
    outlineVariant: const Color(0xFF222C50),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Screens are see-through: the night forest painted behind the whole app shows under them
    // (see AppBackdrop, installed by the MaterialApp builder).
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
