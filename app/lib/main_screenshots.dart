import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/core/app_config.dart';
import 'src/core/mock_nightdrop_core.dart';
import 'src/core/models.dart';

/// **Store screenshots only** — the real UI over the in-memory mock core, seeded with fictional
/// people and conversations. Never part of a release: `main.dart` does not import it, and it is
/// only built with `flutter build apk -t lib/main_screenshots.dart` (see
/// `fastlane/metadata/android/en-US/images/README.md`).
///
/// Fictional on purpose. The listing is public, and a real install shows a real identity tag,
/// onion address and contacts. Nothing here is key material: the mock has no crypto, so its
/// invite QR and short code are random strings — and the pairing shot is still blurred, so nobody
/// mistakes it for a working invite.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  final core = _ScreenshotCore();
  await core.createIdentity();
  runApp(NightdropApp(core: core));
}

class _ScreenshotCore extends MockNightdropCore {
  // Fictional, but shaped like real contact ids (identity keys), since the chat header shows an
  // abbreviated one under the name.
  static const _maya = 'Rk3vQ9mZ2hTf8yLw1cXp7sNd4bJq0uGe6aVoIt5rHkE';
  static const _jonas = 'p8WnC2xLd7QsV0fKz4mRy9TbA1hJg6NeU3oEiX5cDqM';
  static const _ines = 'Yt6HbS1qFw9mKc3zR8vLx2NdP0gJa7UeT4oViQ5sBnC';

  static final _today = DateTime.now();
  static DateTime _at(int hour, int minute) =>
      DateTime(_today.year, _today.month, _today.day, hour, minute);

  final List<Contact> _people = [
    Contact(
      id: _maya,
      theirName: 'Maya',
      verified: true,
      peerVerified: true,
      peerSupportsBurn: true,
    ),
    Contact(id: _jonas, theirName: 'Jonas', peerSupportsBurn: true, disappearingSecs: 86400),
    Contact(id: _ines, theirName: 'Inês', peerSupportsBurn: true),
  ];

  @override
  List<Contact> get contacts => List.unmodifiable(_people);

  @override
  Future<bool> shouldSuggestBackup() async => false;

  // The mock's invite flow fakes an incoming request; a listing shot should not show one.
  @override
  List<Contact> get incomingRequests => const [];

  // The mock's own safety number is 12345 67890 repeated, which reads as fake in a listing.
  @override
  Future<String> safetyNumber(String contactId) async =>
      '60999 42804 86011 59198 56533 02620 19476 71349 37126 93759 62015 88625';

  @override
  List<Message> messagesFor(String contactId) {
    switch (contactId) {
      case _maya:
        return [
          _msg('m1', _maya, 'Did you get the draft I sent over?', false, _at(18, 2)),
          _msg('m2', _maya, 'Got it. Reading it tonight.', true, _at(18, 4)),
          _msg('m3', _maya, 'Sending the door code for Saturday — it burns once you open it.',
              false, _at(18, 6)),
          // Revealed a few seconds ago: the ring is part-way round. Recomputed on every read so the
          // capture shows the same moment however long navigation took.
          Message(
            id: 'maya-m4',
            contactId: _maya,
            text: '4 7 1 9 — the side entrance',
            fromMe: false,
            at: _at(18, 6),
            msgId: 'm4',
            burnSecs: 60,
            viewedAt: DateTime.now().subtract(const Duration(seconds: 21)),
          ),
          Message(
            id: 'maya-m5',
            contactId: _maya,
            text: 'And the Wi-Fi password for the studio',
            fromMe: false,
            at: _at(18, 7),
            msgId: 'm5',
            burnSecs: 30,
          ),
          Message(
            id: 'maya-m6',
            contactId: _maya,
            text: 'Thanks. Here is the address, same rules.',
            fromMe: true,
            at: _at(18, 9),
            msgId: 'm6',
            delivery: 'delivered',
            burnSecs: 300,
          ),
        ];
      case _jonas:
        return [
          _msg('j1', _jonas, 'Train gets in at 9.', false, _at(9, 41)),
          _msg('j2', _jonas, 'I’ll be at the café by the station.', true, _at(9, 43)),
        ];
      case _ines:
        return [
          _msg('i1', _ines, 'Photos from the weekend are up.', false, _at(12, 15)),
        ];
    }
    return const [];
  }

  static Message _msg(String id, String contact, String text, bool mine, DateTime at) => Message(
        id: '$contact-$id',
        contactId: contact,
        text: text,
        fromMe: mine,
        at: at,
        msgId: id,
        delivery: mine ? 'delivered' : '',
      );
}
