import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/l10n/app_localizations.dart';
import 'package:night_drop/src/app.dart';
import 'package:night_drop/src/core/mock_nightdrop_core.dart';
import 'package:night_drop/src/features/groups/group_screens.dart';

Widget _host(MockNightdropCore core, Widget child) => NightdropScope(
      core: core,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

/// A mock core with an identity and one contact to put in a group.
Future<MockNightdropCore> _coreWithContact(WidgetTester tester) async {
  final core = MockNightdropCore();
  await tester.runAsync(() async {
    await core.createIdentity();
    await core.joinWithShortCode('4-cedar-lantern-river');
  });
  return core;
}

void main() {
  testWidgets('a group is created from picked contacts and opens its chat', (tester) async {
    final core = await _coreWithContact(tester);
    await tester.pumpWidget(_host(core, const CreateGroupScreen()));
    await tester.pumpAndSettle();

    // Nobody picked yet: the group cannot be created.
    await tester.tap(find.byKey(const ValueKey('group-create')));
    await tester.pumpAndSettle();
    expect(core.groups, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('group-name')), 'Night shift');
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('group-create')));
    await tester.pumpAndSettle();

    expect(core.groups.single.name, 'Night shift');
    expect(find.byType(GroupChatScreen), findsOneWidget);
    expect(find.text('Night shift'), findsOneWidget);
  });

  testWidgets('a message typed in a group appears in its history', (tester) async {
    final core = await _coreWithContact(tester);
    final id = await core.createGroup('Crew', [core.contacts.first.id]);
    await tester.pumpWidget(_host(core, GroupChatScreen(groupId: id)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('group-input')), 'hello all');
    await tester.tap(find.byKey(const ValueKey('group-send')));
    await tester.pumpAndSettle();

    expect(core.groupMessagesFor(id).single.text, 'hello all');
    expect(find.text('hello all'), findsOneWidget);
  });

  testWidgets('after leaving, the composer is replaced by a notice', (tester) async {
    final core = await _coreWithContact(tester);
    final id = await core.createGroup('Crew', [core.contacts.first.id]);
    await core.leaveGroup(id);
    await tester.pumpWidget(_host(core, GroupChatScreen(groupId: id)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('group-input')), findsNothing);
    expect(find.text('You left this group'), findsOneWidget);
  });
}
