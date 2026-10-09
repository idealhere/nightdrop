import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/src/core/privacy_prefs.dart';

void main() {
  tearDown(() => PrivacyPrefs.hideIncomingPhotos.value = false);

  test('a received photo is concealed until revealed', () {
    PrivacyPrefs.hideIncomingPhotos.value = true;
    expect(PrivacyPrefs.conceals('photo-1'), isTrue);

    var notified = 0;
    void listener() => notified++;
    PrivacyPrefs.changes.addListener(listener);
    PrivacyPrefs.reveal('photo-1');
    PrivacyPrefs.changes.removeListener(listener);

    expect(notified, 1);
    expect(PrivacyPrefs.conceals('photo-1'), isFalse);
    expect(PrivacyPrefs.conceals('photo-2'), isTrue, reason: 'revealing is per photo');
  });

  test('with the setting off nothing is concealed', () {
    PrivacyPrefs.hideIncomingPhotos.value = false;
    expect(PrivacyPrefs.conceals('photo-3'), isFalse);
  });
}
