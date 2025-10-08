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
        return 'S3';
      case PrimerColor.magenta:
        return 'S4';
      case PrimerColor.orange:
        return 'S5';
      case PrimerColor.blue:
        return 'A3';
      case PrimerColor.red:
        return 'A4';
      case PrimerColor.cyan:
        return 'A5';
      case PrimerColor.yellow:
        return 'T2';
      case PrimerColor.pink:
        return 'B2';
      case PrimerColor.purple:
        return 'B3';
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

class EventRecipe {
  EventRecipe({
    required this.id,
    required this.measure,
    required this.position,
    required this.primerAssignments,
  });

  final int id;
  final int? measure;
  final String? position;
  final Map<PrimerColor, PrimerAssignment> primerAssignments;

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
    return EventRecipe(
      id: json['id'] as int,
      measure: json['measure'] as int?,
      position: json['position'] as String?,
      primerAssignments: primer,
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
