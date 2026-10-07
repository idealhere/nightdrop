import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// The app's display language. Russian by default; the user can switch to English and the choice
/// is remembered in a small file in the app's private directory (it holds a language code only).
class AppLocale {
  AppLocale._();

  static const Locale russian = Locale('ru');
  static const Locale english = Locale('en');

  static final ValueNotifier<Locale> current = ValueNotifier<Locale>(russian);

  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/language');

  /// Restore the saved choice. Any failure keeps the default: language must never block startup.
  static Future<void> load() async {
    try {
      final code = (await (await _file()).readAsString()).trim();
      if (code == english.languageCode) current.value = english;
    } catch (_) {}
  }

  static Future<void> toggle() async {
    final next = current.value == russian ? english : russian;
    current.value = next;
    try {
      await (await _file()).writeAsString(next.languageCode);
    } catch (_) {}
  }
}
