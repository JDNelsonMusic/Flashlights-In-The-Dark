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

  group('resolvePrimerAudioPlayFile', () {
    test('normalises short and long primer names', () {
      expect(resolvePrimerAudioPlayFile('short24.mp3'), 'short24.mp3');
      expect(resolvePrimerAudioPlayFile('Long54.mp3'), 'Long54.mp3');
    });

    test('maps legacy a-bank requests onto shipped primer assets', () {
      expect(resolvePrimerAudioPlayFile('a4.mp3'), 'Short4.mp3');
      expect(resolvePrimerAudioPlayFile('A54.mp3'), 'Long54.mp3');
      expect(resolvePrimerAudioPlayFile('a49.mp3'), isNull);
    });
  });

  group('resolveBundledAudioPlayAssetKey', () {
    test('resolves direct legacy b/c/d requests', () {
      expect(
        resolveBundledAudioPlayAssetKey('b7.mp3'),
        'available-sounds/sound-events-LEFT/b7.mp3',
      );
      expect(
        resolveBundledAudioPlayAssetKey('c12.mp3'),
        'available-sounds/sound-events-CENTER/c12.mp3',
      );
      expect(
        resolveBundledAudioPlayAssetKey('d3.mp3'),
        'available-sounds/sound-events-RIGHT/d3.mp3',
      );
    });

    test('maps shipped seL/seC/seR requests onto bundled clip banks', () {
      expect(
        resolveBundledAudioPlayAssetKey('seL-0.mp3'),
        'available-sounds/sound-events-LEFT/b1.mp3',
      );
      expect(
        resolveBundledAudioPlayAssetKey('seC-31.mp3'),
        'available-sounds/sound-events-CENTER/c32.mp3',
      );
      expect(resolveBundledAudioPlayAssetKey('seR-32.mp3'), isNull);
    });
  });
}
