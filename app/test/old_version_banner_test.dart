import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/l10n/app_localizations.dart';
import 'package:night_drop/src/app.dart';
import 'package:night_drop/src/core/mock_nightdrop_core.dart';
import 'package:night_drop/src/features/chat/chat_screen.dart';

/// A core whose single contact can be marked as running an older build.
class _OldVersionCore extends MockNightdropCore {
  void setOld(String contactId, bool old) {
    for (final c in contacts) {
      if (c.id == contactId) c.peerOnOldVersion = old;
    }
    notifyListeners();
  }
}

void main() {
  Future<void> pumpChat(WidgetTester tester, bool old) async {
    final core = _OldVersionCore();
    late final String contactId;
    await tester.runAsync(() async {
      await core.createIdentity();
      contactId = (await core.joinWithShortCode('4-cedar-lantern-river')).id;
    });
    core.setOld(contactId, old);
    await tester.pumpWidget(
      NightdropScope(
        core: core,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatScreen(contactId: contactId),
        ),
      ),
    );
    await tester.pump();
  }

  // Their older app cannot show this, so it has to reach them through the reader.
  testWidgets('a contact on an older version is surfaced, worded to be passed on',
      (tester) async {
    await pumpChat(tester, true);
    expect(find.textContaining('older version of Night Drop'), findsOneWidget);
    expect(find.textContaining('ask them to update'), findsOneWidget);
  });

  // The core sets this only on evidence; the UI must not raise it on its own.
  testWidgets('no banner for a current contact', (tester) async {
    await pumpChat(tester, false);
    expect(find.textContaining('older version of Night Drop'), findsNothing);
  });
}
