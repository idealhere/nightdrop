import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/l10n/app_localizations.dart';
import 'package:night_drop/src/app.dart';
import 'package:night_drop/src/core/models.dart';
import 'package:night_drop/src/core/mock_nightdrop_core.dart';
import 'package:night_drop/src/features/chat/chat_screen.dart';

/// A chat long enough to scroll.
class _LongChatCore extends MockNightdropCore {
  void fill(String contactId, int n) {
    for (var i = 0; i < n; i++) {
      appendForTest(Message(
        id: 'm$i',
        contactId: contactId,
        text: 'message $i',
        fromMe: i.isEven,
        at: DateTime.now(),
        msgId: 'm$i',
      ));
    }
    notifyListeners();
  }
}

void main() {
  Future<ScrollPosition> pumpChat(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final core = _LongChatCore();
    late final String contactId;
    await tester.runAsync(() async {
      await core.createIdentity();
      contactId = (await core.joinWithShortCode('4-cedar-lantern-river')).id;
    });
    core.fill(contactId, 60);
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
    // Opening a chat scrolls to the newest message, with a settle pass for late layout.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    return tester.widget<ListView>(find.byType(ListView)).controller!.position;
  }

  /// The keyboard sliding in over a few frames, as the platform reports it.
  Future<void> slideKeyboard(WidgetTester tester, double to) async {
    final from = tester.view.viewInsets.bottom;
    for (var i = 1; i <= 5; i++) {
      tester.view.viewInsets = FakeViewPadding(bottom: from + (to - from) * i / 5);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('the newest message stays in view while the keyboard opens and closes',
      (tester) async {
    final position = await pumpChat(tester);
    expect(position.pixels, position.maxScrollExtent, reason: 'opened at the newest message');
    expect(find.text('message 59'), findsOneWidget);

    await slideKeyboard(tester, 320);
    expect(position.pixels, position.maxScrollExtent, reason: 'followed the keyboard up');
    expect(find.text('message 59'), findsOneWidget);

    await slideKeyboard(tester, 0);
    expect(position.pixels, position.maxScrollExtent, reason: 'and back down');
    expect(find.text('message 59'), findsOneWidget);
  });

  testWidgets('someone reading older messages is not pulled down by the keyboard',
      (tester) async {
    final position = await pumpChat(tester);
    position.jumpTo(0);
    await tester.pump();

    await slideKeyboard(tester, 320);
    expect(position.pixels, 0, reason: 'left where they were reading');
  });
}
