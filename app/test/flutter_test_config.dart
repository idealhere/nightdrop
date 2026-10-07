import 'dart:async';

import 'package:night_drop/src/core/app_locale.dart';

/// The app opens in Russian by default; the widget tests assert the English template strings, so
/// every test file runs with English selected.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppLocale.current.value = AppLocale.english;
  await testMain();
}
