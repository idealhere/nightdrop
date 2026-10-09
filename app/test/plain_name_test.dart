import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/src/core/models.dart';

void main() {
  test('the header name leaves the rank to the badge', () {
    expect(plainName('Max'), 'Max');
    expect(plainName('Max NightDog'), 'Max');
    expect(plainName('Den CyberDog'), 'Den');
  });

  test('no chosen name reads as Anon, never as the rank', () {
    expect(plainName(''), 'Anon');
    expect(plainName('NightDog'), 'Anon');
    expect(plainName('CyberDog'), 'Anon');
  });

  test('what you call a contact wins over what they call themselves', () {
    final contact = Contact(id: 'c', theirName: 'Max', localName: 'Dana from the shop');
    expect(contact.headerName, 'Dana from the shop');
    expect(Contact(id: 'c').headerName, 'Anon');
    expect(Contact(id: 'c', theirName: 'Max').headerName, 'Max');
  });
}
