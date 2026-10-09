import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/l10n/app_localizations.dart';
import 'package:night_drop/src/app.dart';
import 'package:night_drop/src/core/mock_nightdrop_core.dart';
import 'package:night_drop/src/features/home/my_address_screen.dart';

void main() {
  testWidgets('the address screen shows the address and says what it means', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340); // phone-sized: the whole page fits
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final core = MockNightdropCore();
    await tester.pumpWidget(
      NightdropScope(
        core: core,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MyAddressScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('my-address')), findsOneWidget);
    expect(find.textContaining('static=1'), findsOneWidget);
    expect(find.textContaining('until you accept'), findsOneWidget);
  });
}
