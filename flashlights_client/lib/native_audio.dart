import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper around the platform method channel that plays primer tone
/// assets directly via native audio APIs.
class NativeAudio {
  NativeAudio._();

  static const MethodChannel _channel =
      MethodChannel('ai.keex.flashlights/audioNative');

  /// Triggers playback of the given [fileName] using the platform audio layer.
  ///
  /// The method normalises the provided sample name so native code receives the
  /// canonical asset key (e.g. `available-sounds/primerTones/Short26.mp3`).
  static Future<void> playPrimerTone(String fileName, double volume) async {
    final assetKey = _canonicalAssetKey(fileName);
    if (assetKey.isEmpty) {
      debugPrint('[NativeAudio] Ignoring empty primer tone request for "$fileName"');
      return;
    }

    final payload = <String, dynamic>{
      'assetKey': assetKey,
      'fileName': fileName,
      'volume': volume.clamp(0.0, 1.0),
    };

    await _channel.invokeMethod('playPrimerTone', payload);
  }

  /// Stops any primer tone playback in progress on the native side.
  static Future<void> stopPrimerTone() {
    return _channel.invokeMethod('stopPrimerTone');
  }

  static String _canonicalAssetKey(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';

    value = value.replaceAll('\\', '/');

    value = _stripPrefix(value, 'assets/');
    value = _stripPrefix(value, 'available-sounds/');
    value = _stripPrefix(value, 'primerTones/');

    if (value.isEmpty) return '';

    if (value.contains('/')) {
      // If unexpected subdirectories remain, normalise only the last segment.
      final parts = value.split('/');
      final file = parts.removeLast();
      final normalised = _normaliseFileName(file);
      parts.add(normalised);
      value = parts.join('/');
    } else {
      value = _normaliseFileName(value);
    }

    return 'available-sounds/primerTones/$value';
  }

  static String _normaliseFileName(String file) {
    if (file.isEmpty) return file;
    final lower = file.toLowerCase();
    if (lower.startsWith('short')) {
      return 'Short${file.substring(5)}';
    }
    if (lower.startsWith('long')) {
      return 'Long${file.substring(4)}';
    }
    return file;
  }

  static String _stripPrefix(String value, String prefix) {
    final lowerValue = value.toLowerCase();
    final lowerPrefix = prefix.toLowerCase();
    if (lowerValue.startsWith(lowerPrefix)) {
      return value.substring(prefix.length);
    }
    return value;
  }
}
