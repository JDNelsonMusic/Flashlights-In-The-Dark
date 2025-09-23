import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper around the platform method channel that plays primer tone
/// assets via native audio APIs.
class NativeAudio {
  NativeAudio._();

  static const MethodChannel _channel =
      MethodChannel('ai.keex.flashlights/audioNative');

  static final Map<String, Uint8List> _byteCache = <String, Uint8List>{};
  static final Map<String, Future<Uint8List>> _loadingCache =
      <String, Future<Uint8List>>{};
  static final Set<String> _primersPreloaded = <String>{};
  static Future<void>? _preloadFuture;

  /// Triggers playback of the given [fileName] using the platform audio layer.
  static Future<void> playPrimerTone(String fileName, double volume) async {
    final canonical = _canonicalFileName(fileName);
    if (canonical.isEmpty) {
      debugPrint('[NativeAudio] Ignoring empty primer tone request for "$fileName"');
      return;
    }
    final assetKey = 'available-sounds/primerTones/$canonical';
    final clamped = volume.clamp(0.0, 1.0);
    Uint8List? bytes;
    if (!_primersPreloaded.contains(canonical)) {
      try {
        bytes = await _ensureBytes(canonical, assetKey);
      } catch (e, st) {
        debugPrint('[NativeAudio] Failed to load asset $assetKey: $e');
        debugPrint('$st');
        return;
      }
    }
    final payload = <String, dynamic>{
      'fileName': canonical,
      'assetKey': assetKey,
      'volume': clamped,
    };
    if (bytes != null) {
      payload['bytes'] = bytes;
    }
    await _channel.invokeMethod('playPrimerTone', payload);
    debugPrint('[NativeAudio] Requesting primer: $canonical (asset: $assetKey) @ vol=$clamped');
    if (bytes != null) {
      _primersPreloaded.add(canonical);
    }
  }

  /// Stops any primer tone playback in progress on the native side.
  static Future<void> stopPrimerTone() async {
    await _channel.invokeMethod('stopPrimerTone');
  }

  /// Loads all primer tone assets into memory and primes the native caches.
  static Future<void> preloadPrimerLibrary() {
    _preloadFuture ??= _doPreloadPrimerLibrary();
    return _preloadFuture!;
  }

  static Future<void> _doPreloadPrimerLibrary() async {
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final dynamic decoded = jsonDecode(manifestJson);
      if (decoded is! Map<String, dynamic>) {
        debugPrint('[NativeAudio] Unexpected AssetManifest format');
        return;
      }
      final primerAssets = decoded.keys
          .where((key) => key.startsWith('available-sounds/primerTones/'))
          .where((key) => key.toLowerCase().endsWith('.mp3'))
          .toList()
        ..sort();
      for (final assetKey in primerAssets) {
        final canonical = _canonicalFileName(assetKey);
        if (canonical.isEmpty) {
          continue;
        }
        try {
          final bytes = await _ensureBytes(canonical, assetKey);
          final args = <String, dynamic>{
            'fileName': canonical,
            'assetKey': assetKey,
            'bytes': bytes,
            'volume': 1.0,
          };
          await _channel.invokeMethod('preloadPrimerTone', args);
          _primersPreloaded.add(canonical);
          if (kDebugMode) {
            debugPrint('[NativeAudio] Preloaded $canonical');
          }
        } catch (e) {
          debugPrint('[NativeAudio] Failed to preload $assetKey: $e');
        }
      }
    } catch (e) {
      debugPrint('[NativeAudio] Manifest load failed: $e');
    }
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
