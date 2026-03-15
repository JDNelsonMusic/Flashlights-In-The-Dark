import 'package:flutter_test/flutter_test.dart';
import 'package:flashlights_client/network/osc_messages.dart';
import 'package:flashlights_client/network/osc_packet.dart';

void main() {
  group('EventTrigger OSC codec', () {
    test('encodes and decodes component mode after startAtMs', () {
      final trigger = EventTrigger(7, 11, 12345.0, 'audio_only');
      final roundTripped = EventTrigger.fromOsc(trigger.toOsc());

      expect(roundTripped, isNotNull);
      expect(roundTripped!.index, 7);
      expect(roundTripped.eventId, 11);
      expect(roundTripped.startAtMs, 12345.0);
      expect(roundTripped.componentMode, 'audio_only');
    });

    test('decodes component mode without startAtMs', () {
      final message = OSCMessage(
        OscAddress.eventTrigger.value,
        arguments: <Object>[12, 8, 'lighting_only'],
      );
      final decoded = EventTrigger.fromOsc(message);

      expect(decoded, isNotNull);
      expect(decoded!.index, 12);
      expect(decoded.eventId, 8);
      expect(decoded.startAtMs, isNull);
      expect(decoded.componentMode, 'lighting_only');
    });
  });
}
