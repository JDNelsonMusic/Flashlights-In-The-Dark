import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Caches primer tone assets in memory for low-latency playback.
class PrimerToneLibrary {
  PrimerToneLibrary._();

  static final PrimerToneLibrary instance = PrimerToneLibrary._();

  final Map<String, String> _assetByKey = <String, String>{};
  final Map<String, Future<DeviceFileSource?>> _sourceByKey =
      <String, Future<DeviceFileSource?>>{};
  final AudioCache _cache = AudioCache(prefix: '');
  Future<void>? _warmUpFuture;

  Future<void> warmUp() {
    return _warmUpFuture ??= _indexManifest();
  }

  Future<void> _indexManifest() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest
        .listAssets()
        .where((asset) => asset.startsWith('available-sounds/primerTones/'));

    for (final asset in assets) {
      final canonical = _canonicalKey(asset);
      _assetByKey.putIfAbsent(canonical, () => asset);
    }

    debugPrint('[PrimerToneLibrary] Indexed ${_assetByKey.length} primer tones');
  }

  Future<String?> assetForSample(String sample) async {
    await warmUp();
    final canonical = _canonicalKey(sample);
    final asset = _assetByKey[canonical];
    if (asset == null) {
      debugPrint('[PrimerToneLibrary] Missing asset for "$sample" (key: $canonical)');
    }
    return asset;
  }

  Future<DeviceFileSource?> sourceForSample(String sample) async {
    await warmUp();
    final canonical = _canonicalKey(sample);
    if (_sourceByKey.containsKey(canonical)) {
      return _sourceByKey[canonical];
    }
    final asset = _assetByKey[canonical];
    if (asset == null) {
      debugPrint('[PrimerToneLibrary] Missing asset for "$sample" (key: $canonical)');
      return null;
    }
    final loader = _loadDeviceSource(asset, canonical);
    _sourceByKey[canonical] = loader;
    return loader;
  }

  Future<DeviceFileSource?> _loadDeviceSource(
    String asset,
    String canonical,
  ) async {
    try {
      final path = await _cache.loadPath(asset);
      if (path.isEmpty) {
        debugPrint('[PrimerToneLibrary] Cached path empty for $asset');
        return null;
      }
      return DeviceFileSource(path);
    } catch (e, stack) {
      debugPrint('[PrimerToneLibrary] Failed to cache $asset: $e');
      debugPrint('$stack');
      _sourceByKey.remove(canonical);
      return null;
    }
  }

  String _canonicalKey(String raw) {
    var t = raw.trim().replaceAll('\\', '/');
    if (t.startsWith('assets/')) {
      t = t.substring('assets/'.length);
    }
    if (t.startsWith('available-sounds/')) {
      t = t.substring('available-sounds/'.length);
    }
    if (t.startsWith('primerTones/')) {
      t = t.substring('primerTones/'.length);
    }
    return t.toLowerCase();
  }
}
