import 'package:flutter_test/flutter_test.dart';
import 'package:flashlights_client/network/osc_listener.dart';

void main() {
  group('playbackDelayForStartAtMs', () {
    test('returns zero for missing timestamps', () {
      expect(playbackDelayForStartAtMs(null), Duration.zero);
    });

    test('returns zero for past timestamps', () {
      final now = DateTime.fromMillisecondsSinceEpoch(5_000);
      expect(playbackDelayForStartAtMs(4_250, now: now), Duration.zero);
    });

    test('returns a positive delay for future timestamps', () {
      final now = DateTime.fromMillisecondsSinceEpoch(12_000);
      expect(
        playbackDelayForStartAtMs(12_275, now: now),
        const Duration(milliseconds: 275),
      );
    });
  });
}
