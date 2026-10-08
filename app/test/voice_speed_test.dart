import 'package:flutter_test/flutter_test.dart';
import 'package:night_drop/src/features/chat/voice.dart';

void main() {
  test('the three speeds, starting from normal', () {
    expect(kVoiceSpeeds, [1.0, 1.5, 0.75]);
    expect(voiceSpeed.value, 1.0);
  });

  test('speeds are labelled without a trailing .0', () {
    expect(voiceSpeedLabel(1.0), '1×');
    expect(voiceSpeedLabel(1.5), '1.5×');
    expect(voiceSpeedLabel(0.75), '0.75×');
  });
}
