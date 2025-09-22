import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper around the platform method channel that plays primer tone
/// assets via native audio APIs.
class NativeAudio {
  NativeAudio._();

  static const MethodChannel _channel =
      MethodChannel('ai.keex.flashlights/audioNative');

  /// Triggers playback of the given [fileName] using the platform audio layer.
  static Future<void> playPrimerTone(String fileName, double volume) async {
    final canonical = _canonicalFileName(fileName);
    if (canonical.isEmpty) {
      debugPrint('[NativeAudio] Ignoring empty primer tone request for "$fileName"');
      return;
    }

    final assetKey = 'available-sounds/primerTones/$canonical';
    final clamped = volume.clamp(0.0, 1.0);
    await _channel.invokeMethod('playPrimerTone', {
      'fileName': canonical,
      'assetKey': assetKey,
      'volume': clamped,
    });
    debugPrint('[NativeAudio] Requesting primer: $canonical (asset: $assetKey) @ vol=$clamped');
  }

  /// Stops any primer tone playback in progress on the native side.
  static Future<void> stopPrimerTone() async {
    await _channel.invokeMethod('stopPrimerTone');
  }

  static String _canonicalFileName(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    if (value.contains('/')) {
      value = value.split('/').last;
    }
    final lower = value.toLowerCase();
    if (lower.startsWith('short')) {
      value = 'Short${value.substring(5)}';
    } else if (lower.startsWith('long')) {
      value = 'Long${value.substring(4)}';
    }
    if (!value.toLowerCase().endsWith('.mp3')) {
      value = '$value.mp3';
    }
    return value;
  }
}
