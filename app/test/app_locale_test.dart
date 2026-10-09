import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/src/core/app_locale.dart';

void main() {
  test('a first launch is in English, except on a Russian device', () {
    expect(AppLocale.forDevice('en'), AppLocale.english);
    expect(AppLocale.forDevice('es'), AppLocale.english);
    expect(AppLocale.forDevice('de'), AppLocale.english);
    expect(AppLocale.forDevice('ru'), AppLocale.russian);
  });
}
