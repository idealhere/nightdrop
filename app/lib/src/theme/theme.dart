import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// CyberDog's dark, low-key theme.
ThemeData nightdropTheme() {
  // CyberDog palette: deep night blue surfaces, a restrained violet accent, moonlight cream
  // for the main call to action.
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF9B7CFF),
    brightness: Brightness.dark,
  ).copyWith(
    primary: const Color(0xFF7A62E6),
    onPrimary: const Color(0xFFF5F7FF),
    primaryContainer: const Color(0xFF2A2364),
    onPrimaryContainer: const Color(0xFFE6DEFF),
    secondary: const Color(0xFFB18CFF),
    onSecondary: const Color(0xFF14102B),
    secondaryContainer: const Color(0xFF1C2448),
    onSecondaryContainer: const Color(0xFFF5F7FF),
    tertiary: const Color(0xFFF0E2B6),
    onTertiary: const Color(0xFF17130A),
    surface: const Color(0xFF090D1F),
    onSurface: const Color(0xFFF5F7FF),
    onSurfaceVariant: const Color(0xFFA8B0D0),
    surfaceContainerLowest: const Color(0xFF050816),
    surfaceContainerLow: const Color(0xFF0B1230),
    surfaceContainer: const Color(0xFF10182E),
    surfaceContainerHigh: const Color(0xFF131C36),
    surfaceContainerHighest: const Color(0xFF151F3A),
    outline: const Color(0xFF7C85A3),
    outlineVariant: const Color(0xFF222C50),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Screens are see-through: the night forest painted behind the whole app shows under them
    // (see NightForestBackground, installed by the MaterialApp builder).
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.tertiary,
        foregroundColor: scheme.onTertiary,
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
