import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/src/core/models.dart';

void main() {
  test('no chosen name: the rank alone, following verification', () {
    expect(rankedName('NightDog', verified: false), 'NightDog');
    expect(rankedName('NightDog', verified: true), 'CyberDog');
    expect(rankedName('', verified: false), 'NightDog');
  });

  test('a chosen name goes in front of the rank', () {
    expect(rankedName('Max', verified: false), 'Max NightDog');
    expect(rankedName('Anon', verified: true), 'Anon CyberDog');
  });

  test('a rank word typed into the name is not repeated', () {
    expect(rankedName('Max CyberDog', verified: false), 'Max NightDog');
    expect(rankedName('Max NightDog', verified: true), 'Max CyberDog');
  });
}
