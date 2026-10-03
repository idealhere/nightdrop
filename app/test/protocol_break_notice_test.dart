import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/src/app.dart';
import 'package:night_drop/src/core/mock_nightdrop_core.dart';

/// Lets a test decide whether the "0.2 won't message 0.1 apps" notice is due.
class _NoticeCore extends MockNightdropCore {
  _NoticeCore({required this.due});

  bool due;
  int dismissals = 0;

  @override
  Future<bool> shouldShowProtocolBreakNotice() async => due;

  @override
  Future<void> dismissProtocolBreakNotice() async {
    dismissals++;
    due = false;
  }
}

void main() {
  Future<_NoticeCore> pumpHome(WidgetTester tester, {required bool due}) async {
    final core = _NoticeCore(due: due);
    await tester.runAsync(core.createIdentity);
    await tester.pumpWidget(NightdropApp(core: core));
    await tester.pumpAndSettle();
    return core;
  }

  testWidgets('the notice says 0.2 cannot message 0.1, and Got it dismisses it', (tester) async {
    final core = await pumpHome(tester, due: true);
    // It has to name both versions: "an update is coming" tells nobody that waiting costs them
    // their contacts.
    expect(find.textContaining('0.2'), findsOneWidget);
    expect(find.textContaining('0.1 apps'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(core.dismissals, 1);
    expect(find.textContaining('0.1 apps'), findsNothing);
  });

  testWidgets('nothing is shown once it has been dismissed for this version', (tester) async {
    await pumpHome(tester, due: false);
    expect(find.textContaining('0.1 apps'), findsNothing);
    expect(find.text('Got it'), findsNothing);
  });
}
