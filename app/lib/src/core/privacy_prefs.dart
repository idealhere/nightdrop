import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Privacy choices that live on this device only. Nothing here is sent to anyone.
class PrivacyPrefs {
  PrivacyPrefs._();

  /// Received photos stay concealed until tapped. On by default.
  static final ValueNotifier<bool> hideIncomingPhotos = ValueNotifier<bool>(true);

  /// Photos the user chose to look at, by media id. Kept in memory only: after a restart they
  /// are concealed again, which is the safer side to err on.
  static final Set<String> _revealed = <String>{};

  /// Fires when the set of revealed photos or the setting changes.
  static final ChangeNotifier changes = _Changes();

  static bool conceals(String mediaId) =>
      hideIncomingPhotos.value && mediaId.isNotEmpty && !_revealed.contains(mediaId);

  static void reveal(String mediaId) {
    if (_revealed.add(mediaId)) (changes as _Changes).fire();
  }

  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/privacy_prefs');

  /// Restore saved choices. Any failure keeps the defaults: prefs must never block startup.
  static Future<void> load() async {
    try {
      final saved = await (await _file()).readAsString();
      if (saved.contains('hide_incoming_photos=0')) hideIncomingPhotos.value = false;
    } catch (_) {}
  }

  static Future<void> setHideIncomingPhotos(bool on) async {
    hideIncomingPhotos.value = on;
    (changes as _Changes).fire();
    try {
      await (await _file()).writeAsString('hide_incoming_photos=${on ? 1 : 0}\n');
    } catch (_) {}
  }
}

class _Changes extends ChangeNotifier {
  void fire() => notifyListeners();
}
