import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/l10n/app_localizations.dart';
import 'package:night_drop/src/app.dart';
import 'package:night_drop/src/core/mock_nightdrop_core.dart';
import 'package:night_drop/src/features/chat/chat_screen.dart';
import 'package:night_drop/src/features/pairing/pairing_screen.dart';

void main() {
  // Showing a code and then hunting for the new chat in the list was a dead end: once the other
  // person has joined, the code screen has nothing more to say.
  testWidgets('the invite screen opens the chat once the other person joins', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final core = MockNightdropCore();
    await tester.runAsync(core.createIdentity);
    await tester.pumpWidget(
      NightdropScope(
        core: core,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PairingScreen(),
        ),
      ),
    );
    // The mock's invite brings a pending request with it.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.pump();
    expect(find.byType(ChatScreen), findsNothing);

    // The other person joins and the request is accepted: now there is a chat.
    final joiner = core.incomingRequests.first;
    await tester.runAsync(() => core.authorize(joiner.id, true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byType(PairingScreen), findsNothing);
  });
}
