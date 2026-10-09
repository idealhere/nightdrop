import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/src/core/models.dart';

Message _photo({bool fromMe = true, Duration age = Duration.zero, String delivery = 'sent'}) =>
    Message(
      id: 'c-0',
      contactId: 'c',
      text: '',
      fromMe: fromMe,
      at: DateTime.now().subtract(age),
      kind: 'image',
      mediaId: 'm1',
      transferId: 't1',
      delivery: delivery,
    );

void main() {
  test('our own recent photo can be unsent but not edited', () {
    final m = _photo();
    expect(m.canEdit, isFalse);
    expect(m.canUnsend, isTrue);
    expect(m.unsendId, 't1');
  });

  test('a photo past the window cannot be unsent unless it is still queued', () {
    expect(_photo(age: const Duration(minutes: 20)).canUnsend, isFalse);
    expect(_photo(age: const Duration(minutes: 20), delivery: 'queued').canUnsend, isTrue);
  });

  test('a received photo cannot be unsent', () {
    expect(_photo(fromMe: false).canUnsend, isFalse);
  });

  test('text is named by its message id', () {
    final m = Message(
      id: 'c-1',
      contactId: 'c',
      text: 'hi',
      fromMe: true,
      at: DateTime.now(),
      msgId: 'id1',
    );
    expect(m.canUnsend, isTrue);
    expect(m.unsendId, 'id1');
  });
}
