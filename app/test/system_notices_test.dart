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
      '📸 Вы сделали скриншот. Собеседнику об этом сообщили.',
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

  test('an unknown notice is shown unchanged', () {
    AppLocale.current.value = AppLocale.russian;
    expect(localizeSystemNotice('Something new from a later core.'),
        'Something new from a later core.');
  });
}
