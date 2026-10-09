import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/l10n/app_localizations.dart';
import 'package:night_drop/src/app.dart';
import 'package:night_drop/src/core/mock_nightdrop_core.dart';
import 'package:night_drop/src/core/privacy_prefs.dart';
import 'package:night_drop/src/features/chat/chat_screen.dart';
import 'package:night_drop/src/features/groups/group_screens.dart';
import 'package:night_drop/src/features/home/home_screen.dart';
import 'package:night_drop/src/features/pairing/pairing_screen.dart';

Future<MockNightdropCore> _home(WidgetTester tester, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final core = MockNightdropCore();
  await tester.runAsync(() async {
    await core.createIdentity();
    await core.joinWithShortCode('4-cedar-lantern-river');
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

void main() {
  testWidgets('a phone has three sections along the bottom', (tester) async {
    await _home(tester);
    final bar = find.byType(NavigationBar);
    expect(bar, findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    for (final label in ['Chats', 'Contacts', 'Settings']) {
      expect(find.descendant(of: bar, matching: find.text(label)), findsOneWidget);
    }
    expect(find.descendant(of: bar, matching: find.text('Profile')), findsNothing);
    // The profile and the action button are in the top bar instead.
    expect(find.byKey(const ValueKey('profile-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('new-action')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('the line under the brand switches between chats, contacts and requests',
      (tester) async {
    final core = await _home(tester);
    final person = core.contacts.first.headerName;
    int bottom() => tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

    await tester.tap(find.byKey(const ValueKey('top-tab-1')));
    await tester.pump();
    expect(bottom(), 1, reason: 'the bottom bar follows');
    expect(find.text(person), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('top-tab-2')));
    await tester.pump();
    expect(bottom(), 0, reason: 'requests belong to the chats');
    expect(find.text('No requests'), findsOneWidget);
    expect(find.text(person), findsNothing, reason: 'only requests are listed');

    await tester.tap(find.byKey(const ValueKey('top-tab-0')));
    await tester.pump();
    expect(find.text(person), findsOneWidget);
    expect(find.text('No requests'), findsNothing);
  });

  testWidgets('groups are listed with the chats, people alone under Contacts', (tester) async {
    final core = await _home(tester);
    await core.createGroup('Crew', [core.contacts.first.id]);
    await tester.pump();
    final person = core.contacts.first.headerName;
    expect(find.text('Crew'), findsOneWidget);
    expect(find.text(person), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Contacts')));
    await tester.pump();
    expect(find.text(person), findsOneWidget);
    expect(find.text('Crew'), findsNothing, reason: 'a group is not a contact');

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Chats')));
    await tester.pump();
    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();
    expect(find.byType(GroupChatScreen), findsOneWidget);
  });

  testWidgets('the action button offers a chat, a group and a scan', (tester) async {
    await _home(tester);
    await tester.tap(find.byKey(const ValueKey('new-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-chat')), findsOneWidget);
    expect(find.byKey(const ValueKey('scan-qr')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('new-group')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateGroupScreen), findsOneWidget);
    expect(find.byType(PairingScreen), findsNothing);
  });

  testWidgets('settings are a section; the profile opens from the top bar', (tester) async {
    await _home(tester);
    expect(find.byIcon(Icons.more_vert), findsNothing, reason: 'no second copy of the settings');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-button')));
    await tester.pumpAndSettle();
    expect(find.text('My address'), findsOneWidget);
    expect(find.text('Anon'), findsOneWidget, reason: 'no name chosen yet');
  });

  testWidgets('the avatar can be changed in the profile', (tester) async {
    addTearDown(() => PrivacyPrefs.avatarStyle.value = 1);
    await _home(tester);
    await tester.tap(find.byKey(const ValueKey('profile-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('change-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('avatar-4')));
    await tester.pumpAndSettle();
    expect(PrivacyPrefs.avatarStyle.value, 4);
    expect(find.byKey(const ValueKey('avatar-4')), findsNothing, reason: 'the choice closes');
  });

  testWidgets('on a wide window a chat opens in the pane, and back returns to the list',
      (tester) async {
    final core = await _home(tester, size: const Size(1000, 900));
    final person = core.contacts.first.headerName;

    await tester.tap(find.text(person));
    // The chat slides in and the action button scales out: a few frames, not one.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget, reason: 'the rail stays');

    await tester.pageBack();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text(person), findsOneWidget);
  });

  testWidgets('on a large window the chat opens beside its list, which marks it',
      (tester) async {
    final core = await _home(tester, size: const Size(1500, 900));
    final person = core.contacts.first.headerName;
    expect(find.text('Select a chat'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-action')), findsOneWidget);

    await tester.tap(find.text(person).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Select a chat'), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget, reason: 'the sidebar stays');
    expect(find.byKey(const ValueKey('new-action')), findsOneWidget,
        reason: 'the list, and its button, stay beside the chat');
    expect(find.byType(BackButton), findsNothing, reason: 'nothing to go back to');
  });

  testWidgets('a wide window gets a side rail instead of a bottom bar', (tester) async {
    await _home(tester, size: const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
