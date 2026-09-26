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
  testWidgets('donations screen lists every donation address', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DonationsScreen(),
    ));

    expect(find.text('Monero (XMR)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Zcash (ZEC)'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Zcash (ZEC)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Bitcoin (BTC)'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Bitcoin (BTC)'), findsOneWidget);
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
    final app = (jsonDecode(File('../config/app_config.json').readAsStringSync())
        as Map<String, dynamic>)['app'] as Map<String, dynamic>;
    expect(AppConfig.current.blurb, app['blurb'],
        reason: 'the blurb is what tells donors how private each option is');
  });

  // Tor Browser's "Safest" level disables JavaScript, so the onion site's visitors may only ever
  // see the static HTML. It used to carry a placeholder instead of the Monero address.
  // The README is the one copy that `make config` does not generate, and GitHub is where many
  // people first look.
  test('every donation address is in the README', () {
    final readme = File('../README.md').readAsStringSync();
    for (final c in _configDonations()) {
      final address = (c as Map<String, dynamic>)['address'] as String;
      expect(readme.contains(address), isTrue, reason: '${c['name']} address missing from README.md');
    }
  });

  test('every donation address is in the website without JavaScript', () {
    final html = File('../website/index.html').readAsStringSync();
    expect(html.contains('replace-with-'), isFalse, reason: 'no placeholder addresses');
    for (final c in _configDonations()) {
      final address = (c as Map<String, dynamic>)['address'] as String;
      expect(html.contains(address), isTrue, reason: '${c['name']} address missing from index.html');
    }
  });
}
