import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// The app's display language. English by default, Russian on a device that is itself set to
/// Russian; the user can switch, and the choice is remembered in a small file in the app's private
/// directory (it holds a language code only).
class AppLocale {
  AppLocale._();

  static const Locale russian = Locale('ru');
  static const Locale english = Locale('en');

  static final ValueNotifier<Locale> current = ValueNotifier<Locale>(english);

  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/language');

  /// The language for a first launch: Russian if that is the device's language, English otherwise.
  static Locale forDevice(String languageCode) => languageCode == russian.languageCode ? russian : english;

  /// Restore the saved choice, or fall back to the device's language. Any failure keeps the
  /// default: language must never block startup.
  static Future<void> load() async {
    current.value = forDevice(PlatformDispatcher.instance.locale.languageCode);
    try {
      final code = (await (await _file()).readAsString()).trim();
      if (code == english.languageCode) current.value = english;
      if (code == russian.languageCode) current.value = russian;
    } catch (_) {}
  }

  /// For the few strings produced outside a widget tree (notifications, the foreground
  /// service), where there is no `BuildContext` to look translations up from.
  static String pick(String en, String ru) => current.value == russian ? ru : en;

  static Future<void> toggle() async {
    final next = current.value == russian ? english : russian;
    current.value = next;
    try {
      await (await _file()).writeAsString(next.languageCode);
    } catch (_) {}
  }
}
