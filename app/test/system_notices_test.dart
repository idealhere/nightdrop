import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/src/core/app_locale.dart';
import 'package:night_drop/src/core/system_notices.dart';

void main() {
  tearDown(() => AppLocale.current.value = AppLocale.english);

  const screenshot = '📸 The other person took a screenshot of this chat.';

  test('English leaves the stored notice as it is', () {
    AppLocale.current.value = AppLocale.english;
    expect(localizeSystemNotice(screenshot), screenshot);
  });

  test('Russian translates known notices and keeps their marker', () {
    AppLocale.current.value = AppLocale.russian;
    expect(localizeSystemNotice(screenshot), '📸 Собеседник сделал скриншот этого чата.');
    expect(
      localizeSystemNotice('📸 You took a screenshot. The other person was told.'),
      '📸 Сделан скриншот · собеседник уведомлён',
    );
  });

  test('Russian translates the disappearing-messages timer', () {
    AppLocale.current.value = AppLocale.russian;
    // In the stream: what the timer is now. Who set it is the detail, one tap away.
    const mine = '⏱️ You set disappearing messages to 1 hour(s).';
    const theirs = '⏱️ The other person set disappearing messages to off.';
    expect(localizeSystemNotice(mine), '⏱️ Исчезающие сообщения · 1 ч');
    expect(localizeSystemNotice(theirs), '⏱️ Исчезающие сообщения · выкл');
    expect(noticeDetail(mine), 'Вы установили исчезающие сообщения: 1 ч.');
    expect(noticeDetail(theirs), 'Собеседник установил исчезающие сообщения: выкл.');
    AppLocale.current.value = AppLocale.english;
    expect(localizeSystemNotice(mine), '⏱️ Disappearing messages · 1 h');
    expect(noticeDetail(mine), 'You set disappearing messages to 1 hour(s).');
  });

  test('marker and body are available separately', () {
    AppLocale.current.value = AppLocale.russian;
    expect(noticeMarker(screenshot), '📸');
    expect(noticeBody(screenshot), 'Собеседник сделал скриншот этого чата.');
    expect(noticeMarker('no marker here'), '');
  });

  test('long security and storage notices are shown short, in both languages', () {
    const repaired = '🔄 The other person re-paired, starting a new secure session. Verify it.';
    const stored = '☁️ The other person enabled 24h server storage for this chat. Messages are held.';
    AppLocale.current.value = AppLocale.english;
    expect(localizeSystemNotice(repaired), '🔄 Safety code changed');
    expect(localizeSystemNotice(stored), '☁️ Undelivered kept on server · 24 h');
    expect(noticeDetail(stored), contains('enabled 24h server storage'));
    AppLocale.current.value = AppLocale.russian;
    expect(localizeSystemNotice(repaired), '🔄 Код безопасности изменён');
    expect(localizeSystemNotice(stored), '☁️ Хранение недоставленных · 24 ч');
    expect(
      localizeSystemNotice('✅ Your chat request was approved. You can start talking.'),
      '✅ Запрос принят · можно общаться',
    );
    // A notice with nothing more to say has no detail to open.
    expect(noticeDetail(screenshot), isNull);
    expect(noticeAsksToVerify(repaired), isTrue);
    expect(noticeAsksToVerify(stored), isFalse);
  });

  test('an unknown notice is shown unchanged', () {
    AppLocale.current.value = AppLocale.russian;
    expect(localizeSystemNotice('Something new from a later core.'),
        'Something new from a later core.');
  });
}
