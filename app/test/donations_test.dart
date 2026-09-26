import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/l10n/app_localizations.dart';
import 'package:night_drop/src/core/app_config.dart';
import 'package:night_drop/src/features/donations/donations_screen.dart';

/// The donation list in `config/app_config.json`, which the app bundle and the website share.
List<dynamic> _configDonations() =>
    (jsonDecode(File('../config/app_config.json').readAsStringSync())
        as Map<String, dynamic>)['donations'] as List<dynamic>;

void main() {
  testWidgets('donations screen lists privacy-coin addresses', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DonationsScreen(),
    ));

    expect(find.text('Monero (XMR)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Zcash (ZEC)'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Zcash (ZEC)'), findsOneWidget);
  });

  // `make config` copies the JSON for the app and the site, but not into this compiled fallback,
  // so the two can drift silently — and the fallback is what shows until the asset loads.
  test('the compiled fallback matches config/app_config.json exactly', () {
    final config = _configDonations();
    expect(kDefaultDonations.length, config.length);
    for (var i = 0; i < config.length; i++) {
      final c = config[i] as Map<String, dynamic>;
      final d = kDefaultDonations[i];
      expect([d.name, d.ticker, d.address, d.note],
          [c['name'], c['ticker'], c['address'], c['note']]);
    }
  });

  // Tor Browser's "Safest" level disables JavaScript, so the onion site's visitors may only ever
  // see the static HTML. It used to carry a placeholder instead of the Monero address.
  test('every donation address is in the website without JavaScript', () {
    final html = File('../website/index.html').readAsStringSync();
    expect(html.contains('replace-with-'), isFalse, reason: 'no placeholder addresses');
    for (final c in _configDonations()) {
      final address = (c as Map<String, dynamic>)['address'] as String;
      expect(html.contains(address), isTrue, reason: '${c['name']} address missing from index.html');
    }
  });
}
