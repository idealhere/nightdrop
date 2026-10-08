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
    expect(
      localizeSystemNotice('⏱️ You set disappearing messages to 1 hour(s).'),
      '⏱️ Вы установили исчезающие сообщения: 1 ч.',
    );
    expect(
      localizeSystemNotice('⏱️ The other person set disappearing messages to off.'),
      '⏱️ Собеседник установил исчезающие сообщения: выкл.',
    );
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
    expect(localizeSystemNotice(stored), '☁️ Undelivered messages are kept on the server for 24 h');
    AppLocale.current.value = AppLocale.russian;
    expect(localizeSystemNotice(repaired), '🔄 Код безопасности изменён');
    expect(localizeSystemNotice(stored), '☁️ Хранение недоставленных сообщений: 24 ч');
    expect(noticeAsksToVerify(repaired), isTrue);
    expect(noticeAsksToVerify(stored), isFalse);
  });

  test('an unknown notice is shown unchanged', () {
    AppLocale.current.value = AppLocale.russian;
    expect(localizeSystemNotice('Something new from a later core.'),
        'Something new from a later core.');
  });
}
