import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lightweight index for primer tone assets.
///
/// The native audio layers expect canonical asset paths when triggering
/// playback.  This service normalises incoming sample names (case-insensitive,
/// with or without folder prefixes) and maps them to the exact asset key that
/// Flutter bundled.
class PrimerToneLibrary {
  PrimerToneLibrary._();

  static final PrimerToneLibrary instance = PrimerToneLibrary._();

  final Map<String, String> _assetByKey = <String, String>{};
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
      final canonical = canonicalKey(asset);
      _assetByKey.putIfAbsent(canonical, () => asset);
    }

    debugPrint('[PrimerToneLibrary] Indexed ${_assetByKey.length} primer tones');
  }

  Future<String?> assetForSample(String sample) async {
    await warmUp();
    final canonical = canonicalKey(sample);
    final asset = _assetByKey[canonical];
    if (asset == null) {
      debugPrint('[PrimerToneLibrary] Missing asset for "$sample" (key: $canonical)');
    }
    return asset;
  }

  /// Normalises a primer sample name so lookups remain case-insensitive and
  /// ignore folder prefixes.
  String canonicalKey(String raw) {
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
