import 'dart:async';

import 'package:night_drop/src/core/app_locale.dart';
import 'package:night_drop/src/core/privacy_prefs.dart';

/// The app opens in Russian by default; the widget tests assert the English template strings, so
/// every test file runs with English selected.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppLocale.current.value = AppLocale.english;
  // The existing chat tests look at received images directly; concealment has its own test.
  PrivacyPrefs.hideIncomingPhotos.value = false;
  await testMain();
}
