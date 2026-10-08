import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// What a notification may show.
enum NotificationDetail {
  /// Who wrote and what they wrote.
  full,

  /// Only that a new message arrived.
  private,

  /// Only the app's name.
  hidden,
}

/// Privacy choices that live on this device only. Nothing here is sent to anyone.
class PrivacyPrefs {
  PrivacyPrefs._();

  /// Received photos stay concealed until tapped. On by default.
  static final ValueNotifier<bool> hideIncomingPhotos = ValueNotifier<bool>(true);

  /// How much a notification shows. The default says a message arrived and nothing more.
  static final ValueNotifier<NotificationDetail> notificationDetail =
      ValueNotifier<NotificationDetail>(NotificationDetail.private);

  /// Photos the user chose to look at, by media id. Kept in memory only: after a restart they
  /// are concealed again, which is the safer side to err on.
  static final Set<String> _revealed = <String>{};

  /// Notices at the top of a chat that the user swiped away, by key. Remembered, so a notice
  /// that was read and dismissed does not come back every time the chat opens.
  static final Set<String> _dismissedNotices = <String>{};

  static bool noticeDismissed(String key) => _dismissedNotices.contains(key);

  static Future<void> dismissNotice(String key) async {
    if (!_dismissedNotices.add(key)) return;
    (changes as _Changes).fire();
    await _save();
  }

  /// Fires when the set of revealed photos, a dismissed notice or the setting changes.
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
      for (final level in NotificationDetail.values) {
        if (saved.contains('notification_detail=${level.name}')) notificationDetail.value = level;
      }
      for (final line in saved.split('\n')) {
        if (line.startsWith('dismissed=')) _dismissedNotices.add(line.substring(10));
      }
    } catch (_) {}
  }

  static Future<void> _save() async {
    try {
      await (await _file()).writeAsString(
        'hide_incoming_photos=${hideIncomingPhotos.value ? 1 : 0}\n'
        'notification_detail=${notificationDetail.value.name}\n'
        '${_dismissedNotices.map((k) => 'dismissed=$k\n').join()}',
      );
    } catch (_) {}
  }

  static Future<void> setHideIncomingPhotos(bool on) async {
    hideIncomingPhotos.value = on;
    (changes as _Changes).fire();
    await _save();
  }

  static Future<void> setNotificationDetail(NotificationDetail level) async {
    notificationDetail.value = level;
    await _save();
  }
}

class _Changes extends ChangeNotifier {
  void fire() => notifyListeners();
}
