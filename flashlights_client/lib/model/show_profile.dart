import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class ShowProfile {
  const ShowProfile({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.runtimeReady,
    required this.triggerCount,
    required this.scoreMusicXml,
    required this.triggerPositionSource,
    this.electronicsManifest,
    this.lightShowManifest,
    this.notes,
  });

  final String id;
  final String label;
  final String shortLabel;
  final bool runtimeReady;
  final int triggerCount;
  final String scoreMusicXml;
  final String triggerPositionSource;
  final String? electronicsManifest;
  final String? lightShowManifest;
  final String? notes;

  factory ShowProfile.fromJson(Map<String, dynamic> json) {
    return ShowProfile(
      id: (json['id'] as String?)?.trim() ?? 'unknown',
      label: (json['label'] as String?)?.trim() ?? 'Unknown',
      shortLabel: (json['shortLabel'] as String?)?.trim() ?? 'Unknown',
      runtimeReady: json['runtimeReady'] as bool? ?? false,
      triggerCount: json['triggerCount'] as int? ?? 0,
      scoreMusicXml: (json['scoreMusicXml'] as String?)?.trim() ?? '',
      triggerPositionSource:
          (json['triggerPositionSource'] as String?)?.trim() ?? '',
      electronicsManifest:
          (json['electronicsManifest'] as String?)?.trim(),
      lightShowManifest: (json['lightShowManifest'] as String?)?.trim(),
      notes: (json['notes'] as String?)?.trim(),
    );
  }
}

class ShowProfileManifest {
  const ShowProfileManifest({
    required this.activeProfileId,
    required this.profiles,
  });

  final String activeProfileId;
  final List<ShowProfile> profiles;

  ShowProfile? get activeProfile {
    for (final profile in profiles) {
      if (profile.id == activeProfileId) {
        return profile;
      }
    }
    return null;
  }

  factory ShowProfileManifest.fromJson(Map<String, dynamic> json) {
    final rawProfiles = json['profiles'] as List<dynamic>? ?? const [];
    return ShowProfileManifest(
      activeProfileId:
          (json['activeProfileId'] as String?)?.trim() ?? 'unknown',
      profiles: rawProfiles
          .whereType<Map<String, dynamic>>()
          .map(ShowProfile.fromJson)
          .toList(growable: false),
    );
  }
}

Future<ShowProfileManifest> loadShowProfileManifestAsset() async {
  final raw = await rootBundle.loadString('assets/show_profiles.json');
  final decoded = json.decode(raw) as Map<String, dynamic>;
  return ShowProfileManifest.fromJson(decoded);
}
