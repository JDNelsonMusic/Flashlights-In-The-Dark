import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

enum PrimerColor {
  blue,
  red,
  green,
  purple,
  yellow,
  pink,
  orange,
  magenta,
  cyan,
}

extension PrimerColorDisplay on PrimerColor {
  String get displayName {
    switch (this) {
      case PrimerColor.blue:
        return 'Blue';
      case PrimerColor.red:
        return 'Red';
      case PrimerColor.green:
        return 'Green';
      case PrimerColor.purple:
        return 'Purple';
      case PrimerColor.yellow:
        return 'Yellow';
      case PrimerColor.pink:
        return 'Pink';
      case PrimerColor.orange:
        return 'Orange';
      case PrimerColor.magenta:
        return 'Magenta';
      case PrimerColor.cyan:
        return 'Cyan';
    }
  }

  String get voicePart {
    switch (this) {
      case PrimerColor.green:
        return 'Sop-L1';
      case PrimerColor.magenta:
        return 'Sop-L2';
      case PrimerColor.orange:
        return 'Sop-L2';
      case PrimerColor.blue:
        return 'Alto-L1';
      case PrimerColor.red:
        return 'Alto-L2';
      case PrimerColor.cyan:
        return 'Alto-L2';
      case PrimerColor.yellow:
        return 'Ten-L';
      case PrimerColor.pink:
        return 'Bass-L';
      case PrimerColor.purple:
        return 'Bass-L';
    }
  }

  int get groupIndex {
    switch (this) {
      case PrimerColor.blue:
        return 1;
      case PrimerColor.red:
        return 2;
      case PrimerColor.green:
        return 3;
      case PrimerColor.purple:
        return 4;
      case PrimerColor.yellow:
        return 5;
      case PrimerColor.pink:
        return 6;
      case PrimerColor.orange:
        return 7;
      case PrimerColor.magenta:
        return 8;
      case PrimerColor.cyan:
        return 9;
    }
  }
}

enum ChoirFamily { soprano, alto, tenorBass }

ChoirFamily? choirFamilyFromString(String raw) {
  switch (raw.toLowerCase()) {
    case 'soprano':
      return ChoirFamily.soprano;
    case 'alto':
      return ChoirFamily.alto;
    case 'tenor_bass':
      return ChoirFamily.tenorBass;
    default:
      return null;
  }
}

extension ChoirFamilyAsset on ChoirFamily {
  String get recipeKey {
    switch (this) {
      case ChoirFamily.soprano:
        return 'soprano';
      case ChoirFamily.alto:
        return 'alto';
      case ChoirFamily.tenorBass:
        return 'tenor_bass';
    }
  }
}

PrimerColor? primerColorFromString(String raw) {
  switch (raw.toLowerCase()) {
    case 'blue':
      return PrimerColor.blue;
    case 'red':
      return PrimerColor.red;
    case 'green':
      return PrimerColor.green;
    case 'purple':
      return PrimerColor.purple;
    case 'yellow':
      return PrimerColor.yellow;
    case 'pink':
      return PrimerColor.pink;
    case 'orange':
      return PrimerColor.orange;
    case 'magenta':
      return PrimerColor.magenta;
    case 'cyan':
      return PrimerColor.cyan;
    default:
      return null;
  }
}

class PrimerAssignment {
  PrimerAssignment({required this.sample, this.note});

  final String sample;
  final String? note;

  String get normalizedSample => sample.trim();
}

class ElectronicsAssignment {
  ElectronicsAssignment({
    required this.sample,
    required this.channelMode,
    this.sourceStartMs,
    this.sourceEndMs,
    this.durationMs,
    this.fadeInMs,
    this.fadeOutMs,
    this.timingRule,
  });

  final String sample;
  final String channelMode;
  final double? sourceStartMs;
  final double? sourceEndMs;
  final double? durationMs;
  final double? fadeInMs;
  final double? fadeOutMs;
  final String? timingRule;
}

class LightingKeyframe {
  LightingKeyframe({
    required this.atMs,
    required this.level,
    this.interpolation = 'linear',
  });

  final double atMs;
  final double level;
  final String interpolation;
}

class LightingAssignment {
  LightingAssignment({
    required this.label,
    required this.summary,
    required this.motion,
    required this.peakLevel,
    required this.durationMs,
    required this.keyframes,
  });

  final String label;
  final String summary;
  final String motion;
  final double peakLevel;
  final double durationMs;
  final List<LightingKeyframe> keyframes;
}

class EventLighting {
  EventLighting({
    required this.summary,
    required this.scoreDynamics,
    required this.designTags,
    required this.durationMs,
    required this.parts,
  });

  final String summary;
  final String scoreDynamics;
  final List<String> designTags;
  final double durationMs;
  final Map<String, LightingAssignment> parts;
}

String? _canonicalPrimerSample(String? raw) {
  if (raw == null) {
    return null;
  }
  var value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  if (value.startsWith('./')) {
    value = value.substring(2);
  }
  const prefix = 'primerTones/';
  if (value.toLowerCase().startsWith(prefix.toLowerCase())) {
    value = value.substring(prefix.length);
  }
  var fileName = value;
  final lower = fileName.toLowerCase();
  if (lower.startsWith('short')) {
    fileName = 'Short${lower.substring(5)}';
  } else if (lower.startsWith('long')) {
    fileName = 'Long${lower.substring(4)}';
  }
  if (!fileName.toLowerCase().endsWith('.mp3')) {
    fileName = '$fileName.mp3';
  }
  return '$prefix$fileName';
}

String? _canonicalElectronicsSample(String? raw) {
  if (raw == null) {
    return null;
  }
  var value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  if (value.startsWith('./')) {
    value = value.substring(2);
  }
  if (!value.toLowerCase().endsWith('.mp3')) {
    value = '$value.mp3';
  }
  if (!value.startsWith('available-sounds/')) {
    value = 'available-sounds/$value';
  }
  return value;
}

class EventRecipe {
  EventRecipe({
    required this.id,
    required this.measure,
    required this.measureToken,
    required this.scoreMeasureOrdinal,
    required this.position,
    required this.scoreLabel,
    required this.primerAssignments,
    required this.electronicsAssignments,
    required this.electronicsByPart,
    required this.lighting,
  });

  final int id;
  // Official trigger-score measure for this event, not the sung-note onset.
  final int? measure;
  // Exact displayed measure token from the cut score, e.g. "38.2".
  final String? measureToken;
  // Ordinal position in the currently loaded score asset for OSMD windowing.
  final int? scoreMeasureOrdinal;
  // Official trigger-score beat position for this event, not the sung-note onset.
  final String? position;
  final String? scoreLabel;
  final Map<PrimerColor, PrimerAssignment> primerAssignments;
  final Map<ChoirFamily, ElectronicsAssignment> electronicsAssignments;
  final Map<String, ElectronicsAssignment> electronicsByPart;
  final EventLighting? lighting;

  String get displayMeasureText {
    final token = measureToken?.trim();
    if (token != null && token.isNotEmpty) {
      return token;
    }
    if (measure != null) {
      return '$measure';
    }
    return '—';
  }

  static EventRecipe fromJson(Map<String, dynamic> json) {
    final primer = <PrimerColor, PrimerAssignment>{};
    final primerJson = json['primer'] as Map<String, dynamic>?;
    if (primerJson != null) {
      primerJson.forEach((key, value) {
        final color = primerColorFromString(key);
        if (color != null && value is Map<String, dynamic>) {
          final sample = _canonicalPrimerSample(value['sample'] as String?);
          final note = (value['note'] as String?)?.trim();
          if (sample != null && sample.isNotEmpty) {
            primer[color] = PrimerAssignment(sample: sample, note: note);
          }
        }
      });
    }

    final electronics = <ChoirFamily, ElectronicsAssignment>{};
    final electronicsJson = json['electronics'] as Map<String, dynamic>?;
    if (electronicsJson != null) {
      electronicsJson.forEach((key, value) {
        final family = choirFamilyFromString(key);
        if (family == null || value is! Map<String, dynamic>) {
          return;
        }
        final sample = _canonicalElectronicsSample(value['sample'] as String?);
        final channelMode = (value['channelMode'] as String?)?.trim();
        if (sample == null ||
            sample.isEmpty ||
            channelMode == null ||
            channelMode.isEmpty) {
          return;
        }
        electronics[family] = ElectronicsAssignment(
          sample: sample,
          channelMode: channelMode,
          sourceStartMs: (value['sourceStartMs'] as num?)?.toDouble(),
          sourceEndMs: (value['sourceEndMs'] as num?)?.toDouble(),
          durationMs: (value['durationMs'] as num?)?.toDouble(),
          fadeInMs: (value['fadeInMs'] as num?)?.toDouble(),
          fadeOutMs: (value['fadeOutMs'] as num?)?.toDouble(),
          timingRule: (value['timingRule'] as String?)?.trim(),
        );
      });
    }

    final electronicsByPart = <String, ElectronicsAssignment>{};
    final electronicsByPartJson =
        json['electronicsByPart'] as Map<String, dynamic>?;
    if (electronicsByPartJson != null) {
      electronicsByPartJson.forEach((key, value) {
        if (value is! Map<String, dynamic>) {
          return;
        }
        final sample = _canonicalElectronicsSample(value['sample'] as String?);
        final channelMode = (value['channelMode'] as String?)?.trim();
        if (sample == null ||
            sample.isEmpty ||
            channelMode == null ||
            channelMode.isEmpty) {
          return;
        }
        electronicsByPart[key] = ElectronicsAssignment(
          sample: sample,
          channelMode: channelMode,
          sourceStartMs: (value['sourceStartMs'] as num?)?.toDouble(),
          sourceEndMs: (value['sourceEndMs'] as num?)?.toDouble(),
          durationMs: (value['durationMs'] as num?)?.toDouble(),
          fadeInMs: (value['fadeInMs'] as num?)?.toDouble(),
          fadeOutMs: (value['fadeOutMs'] as num?)?.toDouble(),
          timingRule: (value['timingRule'] as String?)?.trim(),
        );
      });
    }

    EventLighting? lighting;
    final lightingJson = json['lighting'] as Map<String, dynamic>?;
    if (lightingJson != null) {
      final partAssignments = <String, LightingAssignment>{};
      final partsJson = lightingJson['parts'] as Map<String, dynamic>?;
      if (partsJson != null) {
        partsJson.forEach((key, value) {
          if (value is! Map<String, dynamic>) {
            return;
          }
          final label = (value['label'] as String?)?.trim();
          final summary = (value['summary'] as String?)?.trim();
          final motion = (value['motion'] as String?)?.trim();
          final peakLevel = (value['peakLevel'] as num?)?.toDouble();
          final durationMs = (value['durationMs'] as num?)?.toDouble();
          final rawKeyframes = value['keyframes'] as List<dynamic>? ?? const [];
          final keyframes = rawKeyframes
              .whereType<Map<String, dynamic>>()
              .map((entry) {
                final atMs = (entry['atMs'] as num?)?.toDouble();
                final level = (entry['level'] as num?)?.toDouble();
                final interpolation =
                    (entry['interpolation'] as String?)?.trim() ?? 'linear';
                if (atMs == null || level == null) {
                  return null;
                }
                return LightingKeyframe(
                  atMs: atMs,
                  level: level,
                  interpolation: interpolation,
                );
              })
              .whereType<LightingKeyframe>()
              .toList(growable: false);
          if (label == null ||
              summary == null ||
              motion == null ||
              peakLevel == null ||
              durationMs == null ||
              keyframes.isEmpty) {
            return;
          }
          partAssignments[key] = LightingAssignment(
            label: label,
            summary: summary,
            motion: motion,
            peakLevel: peakLevel,
            durationMs: durationMs,
            keyframes: keyframes,
          );
        });
      }

      final summary = (lightingJson['summary'] as String?)?.trim();
      final scoreDynamics = (lightingJson['scoreDynamics'] as String?)?.trim();
      final durationMs = (lightingJson['durationMs'] as num?)?.toDouble();
      final designTags = (lightingJson['designTags'] as List<dynamic>? ??
              const [])
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);

      if (summary != null &&
          scoreDynamics != null &&
          durationMs != null &&
          partAssignments.isNotEmpty) {
        lighting = EventLighting(
          summary: summary,
          scoreDynamics: scoreDynamics,
          designTags: designTags,
          durationMs: durationMs,
          parts: partAssignments,
        );
      }
    }

    return EventRecipe(
      id: json['id'] as int,
      measure: json['measure'] as int?,
      measureToken: (json['measureToken'] as String?)?.trim(),
      scoreMeasureOrdinal: json['scoreMeasureOrdinal'] as int?,
      position: json['position'] as String?,
      scoreLabel: (json['scoreLabel'] as String?)?.trim(),
      primerAssignments: primer,
      electronicsAssignments: electronics,
      electronicsByPart: electronicsByPart,
      lighting: lighting,
    );
  }
}

class EventRecipeBundle {
  EventRecipeBundle({required this.events});

  final List<EventRecipe> events;

  static EventRecipeBundle fromJson(Map<String, dynamic> json) {
    final eventsJson = json['events'] as List<dynamic>? ?? const [];
    final events = eventsJson
        .whereType<Map<String, dynamic>>()
        .map(EventRecipe.fromJson)
        .toList(growable: false);
    return EventRecipeBundle(events: events);
  }
}

Future<List<EventRecipe>> loadEventRecipesAsset() async {
  final raw = await rootBundle.loadString('assets/event_recipes.json');
  final decoded = json.decode(raw) as Map<String, dynamic>;
  return EventRecipeBundle.fromJson(decoded).events;
}
