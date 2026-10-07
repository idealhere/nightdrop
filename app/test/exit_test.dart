import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/l10n/app_localizations.dart';
import 'package:night_drop/src/app.dart';
import 'package:night_drop/src/core/mock_nightdrop_core.dart';
import 'package:night_drop/src/features/home/home_screen.dart';

/// Issue #15: leave the network and close the app, keeping the identity.
class _ExitCore extends MockNightdropCore {
  int exits = 0;
  int logouts = 0;

  @override
  Future<void> exitApp() async => exits++;

  @override
  Future<int> logout() async {
    logouts++;
    return super.logout();
  }
}

void main() {
  Future<_ExitCore> pumpHome(WidgetTester tester) async {
    final core = _ExitCore();
    await tester.runAsync(() async {
      await core.createIdentity();
    });
    await tester.pumpWidget(
      NightdropScope(
        core: core,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    return core;
  }

  Future<void> openExit(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();
  }

  testWidgets('Exit says what it keeps, and cancelling does nothing', (tester) async {
    final core = await pumpHome(tester);
    await openExit(tester);

    expect(find.text('Exit CyberDog?'), findsOneWidget);
    expect(find.textContaining('identity and chats stay'), findsOneWidget,
        reason: 'the harmless way out must say it is harmless, next to the one that is not');
    expect(find.textContaining('up to 24 hours'), findsOneWidget,
        reason: 'what Exit costs is mail that expires on the relay if the app stays closed');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(core.exits, 0);
    expect(core.logouts, 0);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('confirming Exit closes the app and never logs out', (tester) async {
    final core = await pumpHome(tester);
    await openExit(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Exit'));
    await tester.pump();
    await tester.pump();

    expect(core.exits, 1);
    expect(core.logouts, 0, reason: 'Exit keeps the identity');
    expect(core.identity, isNotNull);
    expect(find.text('Disconnecting from Tor…'), findsOneWidget,
        reason: 'the shutdown can take seconds; the screen must not look frozen');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
