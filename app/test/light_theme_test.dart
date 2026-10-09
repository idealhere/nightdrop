import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/src/theme/cyberdog.dart';
import 'package:night_drop/src/theme/theme.dart';

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final scheme = nightdropTheme().colorScheme;

  test('the app is light', () {
    expect(scheme.brightness, Brightness.light);
    expect(scheme.surface.computeLuminance(), greaterThan(0.85));
  });

  test('text stays readable on the light surfaces', () {
    expect(_contrast(scheme.onSurface, scheme.surface), greaterThan(7));
    expect(_contrast(scheme.onSurfaceVariant, scheme.surface), greaterThan(4.5));
    // An incoming bubble and the cards are panels.
    expect(_contrast(scheme.onSurface, CyberDog.panel), greaterThan(7));
    expect(_contrast(scheme.onSurfaceVariant, CyberDog.panel), greaterThan(4.5));
  });

  test('the accent carries white text and reads as an icon on white', () {
    expect(_contrast(scheme.onPrimary, scheme.primary), greaterThan(4));
    // The darker end of an outgoing bubble, under its white text.
    expect(_contrast(Colors.white, CyberDog.outgoing.colors.last), greaterThan(4));
    expect(_contrast(CyberDog.accentLight, CyberDog.panel), greaterThan(3));
    expect(_contrast(CyberDog.rankInk, CyberDog.panel), greaterThan(2.5));
  });

  test('a chat keeps its avatar colour, and different chats differ', () {
    expect(CyberDogAvatar.paletteFor('abc'), CyberDogAvatar.paletteFor('abc'));
    final seen = {for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) CyberDogAvatar.paletteFor(id)};
    expect(seen.length, greaterThan(4));
  });

  testWidgets('a person has the dog for an avatar, a group its sign', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: nightdropTheme(),
      home: const Row(children: [
        CyberDogAvatar(seed: 'x', label: 'karlson'),
        CyberDogAvatar(seed: 'y', label: 'New', group: true),
      ]),
    ));
    expect(find.byType(CyberDogLogo), findsOneWidget);
    expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
  });
}
