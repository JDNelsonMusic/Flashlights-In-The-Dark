import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper around the platform method channel that plays primer tone
/// assets via native audio APIs.
class NativeAudio {
  NativeAudio._();

  static const MethodChannel _channel = MethodChannel(
    'ai.keex.flashlights/audioNative',
  );

  static Completer<void>? _readyCompleter;
  static bool _initialising = false;
  static Map<String, dynamic>? _lastInitSnapshot;
  static Object? _lastInitError;
  static Timer? _retryTimer;
  static Future<Map<String, dynamic>>? _assetManifestFuture;

  static bool get _isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      default:
        return false;
    }
  }

  /// Returns whether the native layer reports the primer library as prepared.
  static bool get isReady => _readyCompleter?.isCompleted ?? false;

  /// Last diagnostics snapshot provided by the platform after initialisation.
  static Map<String, dynamic>? get lastInitSnapshot => _lastInitSnapshot;

  /// Last initialisation error surfaced by the native layer, if any.
  static Object? get lastInitError => _lastInitError;

  /// Ensures the native audio engine has loaded every primer tone into memory.
  static Future<void> ensureInitialized() {
    if (!_isSupportedPlatform) {
      final ready = _readyCompleter ??= Completer<void>()..complete();
      return ready.future;
    }
    final completer = _readyCompleter ??= Completer<void>();
    if (completer.isCompleted) {
      return completer.future;
    }
    if (!_initialising) {
      _initialising = true;
      () async {
        try {
          final manifest = await _primeAssets();
          final value = await _channel.invokeMapMethod<String, dynamic>(
            'initializePrimerLibrary',
            manifest,
          );

          if (value != null) {
            final snapshot = Map<String, dynamic>.unmodifiable(value);
            _lastInitSnapshot = snapshot;
            final status = snapshot['status'] as String?;
            final count = snapshot['count'] ?? snapshot['sounds'];
            debugPrint(
              '[NativeAudio] Primer library ready (${count ?? 'n/a'} assets, status=${status ?? 'unknown'})',
            );

            if (status == 'failed') {
              throw PlatformException(
                code: 'INIT_FAILED',
                message: 'Primer preload returned failed status',
                details: snapshot,
              );
            }
          } else {
            _lastInitSnapshot = null;
            debugPrint('[NativeAudio] Primer library ready (no diagnostics)');
          }

          _lastInitError = null;
          _retryTimer?.cancel();
          _retryTimer = null;
          if (!completer.isCompleted) {
            completer.complete();
          }
        } catch (error, stack) {
          debugPrint('[NativeAudio] Primer initialisation failed: $error');
          _lastInitError = error;
          if (!completer.isCompleted) {
            completer.completeError(error, stack);
          }
          _readyCompleter = null;
          _retryTimer ??= Timer(const Duration(seconds: 2), () {
            _retryTimer = null;
            if (_readyCompleter == null) {
              ensureInitialized();
            }
          });
        } finally {
          _initialising = false;
        }
      }();
    }
    return completer.future;
  }

  static Future<Map<String, dynamic>> _primeAssets() async {
    final decoded = await _loadAssetManifest();
    final primerAssets =
        decoded.keys
            .where((key) => key.startsWith('available-sounds/primerTones/'))
            .where((key) => key.toLowerCase().endsWith('.mp3'))
            .toList()
          ..sort();
    final canonical =
        primerAssets.map((asset) => _canonicalFileName(asset)).toList();

    return <String, dynamic>{
      'assets': primerAssets,
      'canonical': canonical,
      'requested': primerAssets.length,
      'bundledAssetCount': decoded.length,
      'generatedAt': DateTime.now().toIso8601String(),
    };
  }

  static Future<Map<String, dynamic>> _loadAssetManifest() {
    return _assetManifestFuture ??= () async {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final decoded = jsonDecode(manifestJson);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('AssetManifest.json was not a map');
      }
      return decoded;
    }();
  }

  /// Triggers playback of the given [fileName] using the platform audio layer.
  static Future<void> playPrimerTone(String fileName, double volume) async {
    await ensureInitialized();
    final canonical = _canonicalFileName(fileName);
    if (canonical.isEmpty) {
      debugPrint(
        '[NativeAudio] Ignoring empty primer tone request for "$fileName"',
      );
      return;
    }

    final payload = <String, dynamic>{
      'fileName': canonical,
      'volume': volume.clamp(0.0, 1.0),
    };
    await _channel.invokeMethod('playPrimerTone', payload);
  }

  /// Plays a bundled event-electronics clip directly from the Flutter asset tree.
  static Future<void> playElectronicsClip(
    String assetKey,
    double volume,
  ) async {
    final trimmed = assetKey.trim();
    if (trimmed.isEmpty) {
      debugPrint('[NativeAudio] Ignoring empty electronics clip request');
      return;
    }

    final manifest = await _loadAssetManifest();
    if (!manifest.containsKey(trimmed)) {
      throw StateError('Bundled electronics asset not found: $trimmed');
    }

    final payload = <String, dynamic>{
      'assetKey': trimmed,
      'volume': volume.clamp(0.0, 1.0),
    };
    await _channel.invokeMethod('playEventClip', payload);
  }

  /// Stops any native playback in progress on the platform side.
  static Future<void> stopPrimerTone() async {
    await ensureInitialized();
    await _channel.invokeMethod('stopPrimerTone');
  }

  /// Requests a fresh diagnostics snapshot from the native layer.
  static Future<Map<String, dynamic>?> diagnostics() async {
    try {
      final payload = await _channel.invokeMapMethod<String, dynamic>(
        'diagnostics',
      );
      return payload == null
          ? null
          : Map<String, dynamic>.unmodifiable(payload);
    } catch (e) {
      debugPrint('[NativeAudio] Diagnostics request failed: $e');
      return null;
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
}
