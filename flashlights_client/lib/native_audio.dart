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
    Uint8List bytes;
    try {
      bytes = await _ensureBytes(canonical, assetKey);
    } catch (e, st) {
      debugPrint('[NativeAudio] Failed to load asset $assetKey: $e');
      debugPrint('$st');
      return;
    }
    final payload = <String, dynamic>{
      'fileName': canonical,
      'assetKey': assetKey,
      'volume': clamped,
      'bytes': bytes,
    };
    await _channel.invokeMethod('playPrimerTone', payload);
    debugPrint('[NativeAudio] Requesting primer: $canonical (asset: $assetKey) @ vol=$clamped');
  }

  /// Stops any primer tone playback in progress on the native side.
  static Future<void> stopPrimerTone() async {
    await _channel.invokeMethod('stopPrimerTone');
  }

  /// Normalise a primer tone filename so native code can locate the asset.
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

  static final Map<String, Uint8List> _byteCache = <String, Uint8List>{};
  static final Map<String, Future<Uint8List>> _loadingCache = <String, Future<Uint8List>>{};

  static Future<Uint8List> _ensureBytes(String canonical, String assetKey) {
    final cached = _byteCache[canonical];
    if (cached != null) {
      return SynchronousFuture<Uint8List>(cached);
    }
    final pending = _loadingCache[canonical];
    if (pending != null) {
      return pending;
    }
    final future = _loadAndCacheBytes(canonical, assetKey);
    _loadingCache[canonical] = future;
    return future;
  }

  static Future<Uint8List> _loadAndCacheBytes(String canonical, String assetKey) async {
    try {
      final data = await rootBundle.load(assetKey);
      final bytes = data.buffer.asUint8List();
      _byteCache[canonical] = bytes;
      return bytes;
    } finally {
      _loadingCache.remove(canonical);
    }
  }
}
