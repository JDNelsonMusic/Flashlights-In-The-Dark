import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper around the platform method channel that prewarms and plays
/// bundled audio assets via native audio APIs.
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

  /// Returns whether the native layer reports the native audio libraries as prepared.
  static bool get isReady => _readyCompleter?.isCompleted ?? false;

  /// Last diagnostics snapshot provided by the platform after initialisation.
  static Map<String, dynamic>? get lastInitSnapshot => _lastInitSnapshot;

  /// Last initialisation error surfaced by the native layer, if any.
  static Object? get lastInitError => _lastInitError;

  /// Ensures the native audio engine has preloaded its bundled libraries.
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
          final primerManifest = await _primePrimerAssets();
          final primerValue = await _channel.invokeMapMethod<String, dynamic>(
            'initializePrimerLibrary',
            primerManifest,
          );
          final electronicsManifest = await _primeElectronicsAssets();
          final electronicsValue = await _channel
              .invokeMapMethod<String, dynamic>(
                'initializeElectronicsLibrary',
                electronicsManifest,
              );

          if (primerValue != null || electronicsValue != null) {
            final snapshot = <String, dynamic>{
              if (primerValue != null) ...primerValue,
              if (electronicsValue != null) 'electronics': electronicsValue,
            };
            final frozenSnapshot = Map<String, dynamic>.unmodifiable(snapshot);
            _lastInitSnapshot = frozenSnapshot;
            final status = snapshot['status'] as String?;
            final count = snapshot['count'] ?? snapshot['sounds'];
            debugPrint(
              '[NativeAudio] Primer library ready (${count ?? 'n/a'} assets, status=${status ?? 'unknown'})',
            );

            final electronicsStatus =
                electronicsValue == null
                    ? null
                    : electronicsValue['status'] as String?;
            if (status == 'failed' || electronicsStatus == 'failed') {
              throw PlatformException(
                code: 'INIT_FAILED',
                message: 'Native audio preload returned failed status',
                details: frozenSnapshot,
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

  static Future<Map<String, dynamic>> _primePrimerAssets() async {
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

  static Future<Map<String, dynamic>> _primeElectronicsAssets() async {
    final decoded = await _loadAssetManifest();
    final electronicsAssets =
        decoded.keys
            .where(
              (key) =>
                  key.startsWith(
                    'available-sounds/electronics-trigger-clips/',
                  ) &&
                  key.toLowerCase().endsWith('.mp3'),
            )
            .toList()
          ..sort();

    return <String, dynamic>{
      'assets': electronicsAssets,
      'requested': electronicsAssets.length,
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
  static Future<Map<String, dynamic>?> playElectronicsClip(
    String assetKey,
    double volume, {
    Duration startDelay = Duration.zero,
    double? requestedStartAtMs,
  }) async {
    await ensureInitialized();
    final trimmed = assetKey.trim();
    if (trimmed.isEmpty) {
      debugPrint('[NativeAudio] Ignoring empty electronics clip request');
      return null;
    }

    final manifest = await _loadAssetManifest();
    if (!manifest.containsKey(trimmed)) {
      throw StateError('Bundled electronics asset not found: $trimmed');
    }

    final payload = <String, dynamic>{
      'assetKey': trimmed,
      'volume': volume.clamp(0.0, 1.0),
      'startDelayMs': startDelay.inMilliseconds,
      if (requestedStartAtMs != null) 'requestedStartAtMs': requestedStartAtMs,
    };
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'playEventClip',
      payload,
    );
    return response == null
        ? null
        : Map<String, dynamic>.unmodifiable(response);
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
