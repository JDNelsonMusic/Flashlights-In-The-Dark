
import 'package:flutter/services.dart' show rootBundle;
import 'package:xml/xml.dart';

import 'package:flashlights_client/model/event_recipe.dart';

const String _kScoreAssetPath = 'assets/FlashlightsInTheDark_SingerScore23.musicxml';

const Set<String> _kLightChorusPartIds = {
  'P4', // Soprano 3
  'P5', // Soprano 4
  'P6', // Soprano 5
  'P7', // Alto 3
  'P8', // Alto 4
  'P9', // Alto 5
  'P10', // Tenor 2
  'P11', // Baritone 2
  'P12', // Bass 3
};

class _PartSelection {
  const _PartSelection({required this.partId});

  final String partId;
}

const Map<PrimerColor, _PartSelection> _kPrimerColorPartMap = {
  PrimerColor.green: _PartSelection(partId: 'P4'),
  PrimerColor.magenta: _PartSelection(partId: 'P5'),
  PrimerColor.orange: _PartSelection(partId: 'P6'),
  PrimerColor.blue: _PartSelection(partId: 'P7'),
  PrimerColor.red: _PartSelection(partId: 'P8'),
  PrimerColor.cyan: _PartSelection(partId: 'P9'),
  PrimerColor.yellow: _PartSelection(partId: 'P10'),
  PrimerColor.pink: _PartSelection(partId: 'P11'),
  PrimerColor.purple: _PartSelection(partId: 'P12'),
};

const String _kDefaultNoteColor = '#000000';
const String _kHighlightNoteColor = '#0C7F79';
const String _kHighlightDataAttribute = 'data-primer-highlight';

final Map<PrimerColor?, String> _cachedBaseXmlByColor = {};

class _ParsedPitch {
  const _ParsedPitch({required this.step, required this.alter, required this.octave});

  final String step;
  final int alter;
  final int octave;
}

Future<String> loadBaseTrimmedMusicXML({PrimerColor? forColor}) async {
  final cached = _cachedBaseXmlByColor[forColor];
  if (cached != null) {
    return cached;
  }

  final raw = await rootBundle.loadString(_kScoreAssetPath);
  final document = XmlDocument.parse(raw);

  final allowedPartIds = <String>{};
  if (forColor != null) {
    final selection = _kPrimerColorPartMap[forColor];
    if (selection != null) {
      allowedPartIds.add(selection.partId);
    }
  }
  if (allowedPartIds.isEmpty) {
    allowedPartIds.addAll(_kLightChorusPartIds);
  }

  final root = document.rootElement;
  final partList = root.getElement('part-list');
  if (partList != null) {
    final removable = partList.children
        .whereType<XmlElement>()
        .where(
          (element) =>
              element.name.local == 'score-part' &&
              !allowedPartIds.contains(element.getAttribute('id')),
        )
        .toList(growable: false);
    for (final element in removable) {
      element.parent?.children.remove(element);
    }
  }

  final removableParts = root.children
      .whereType<XmlElement>()
      .where(
        (element) =>
            element.name.local == 'part' &&
            !allowedPartIds.contains(element.getAttribute('id')),
      )
      .toList(growable: false);
  for (final part in removableParts) {
    part.parent?.children.remove(part);
  }

  _normaliseNoteColors(root: root, allowedPartIds: allowedPartIds);

  final xml = document.toXmlString(pretty: false);
  _cachedBaseXmlByColor[forColor] = xml;
  return xml;
}

Future<String> loadTrimmedMusicXML({
  PrimerColor? forColor,
  int? highlightMeasure,
  String? highlightNote,
}) async {
  final baseXml = await loadBaseTrimmedMusicXML(forColor: forColor);

  final parsedPitch = highlightNote == null ? null : _parseNoteLabel(highlightNote);
  if (highlightMeasure == null || parsedPitch == null) {
    return baseXml;
  }

  final document = XmlDocument.parse(baseXml);
  _applyPrimerHighlight(
    document,
    measureNumber: highlightMeasure,
    pitch: parsedPitch,
  );
  return document.toXmlString(pretty: false);
}

void _normaliseNoteColors({
  required XmlElement root,
  required Set<String> allowedPartIds,
}) {
  for (final part in root.children.whereType<XmlElement>()) {
    if (part.name.local != 'part') {
      continue;
    }
    final partId = part.getAttribute('id');
    if (!allowedPartIds.contains(partId)) {
      continue;
    }
    for (final note in part.findElements('note')) {
      _setNoteHighlight(note, isHighlighted: false);
    }
  }
}

void _applyPrimerHighlight(
  XmlDocument document, {
  required int measureNumber,
  required _ParsedPitch pitch,
}) {
  final root = document.rootElement;
  for (final part in root.findElements('part')) {
    for (final measure in part.findElements('measure')) {
      final parsedNumber = _parseMeasureNumber(measure.getAttribute('number'));
      if (parsedNumber == null || parsedNumber != measureNumber) {
        continue;
      }
      for (final note in measure.findElements('note')) {
        if (_noteMatchesPitch(note, pitch)) {
          _setNoteHighlight(note, isHighlighted: true);
        }
      }
    }
  }
}

void _setNoteHighlight(XmlElement note, {required bool isHighlighted}) {
  if (note.getElement('rest') != null) {
    _removeHighlightAttributes(note);
    return;
  }

  final targetColor = isHighlighted ? _kHighlightNoteColor : _kDefaultNoteColor;
  final existing = note.getAttributeNode('color');
  if (existing != null) {
    existing.value = targetColor;
  } else {
    note.attributes.add(XmlAttribute(XmlName('color'), targetColor));
  }

  _removeHighlightAttributes(note);
  if (isHighlighted) {
    note.attributes.add(
      XmlAttribute(XmlName(_kHighlightDataAttribute), 'true'),
    );
  }
}

void _removeHighlightAttributes(XmlElement note) {
  note.attributes.removeWhere(
    (attribute) => attribute.name.local == _kHighlightDataAttribute,
  );
}

_ParsedPitch? _parseNoteLabel(String raw) {
  final match = RegExp(r'^([A-Ga-g])(bb|##|b|#)?(\d+)$').firstMatch(raw.trim());
  if (match == null) {
    return null;
  }
  final step = match.group(1)!.toUpperCase();
  final accidental = match.group(2);
  final octaveString = match.group(3);
  final octave = int.tryParse(octaveString ?? '');
  if (octave == null) {
    return null;
  }
  final alter = _alterFromAccidental(accidental);
  return _ParsedPitch(step: step, alter: alter, octave: octave);
}

int _alterFromAccidental(String? accidental) {
  switch (accidental) {
    case 'bb':
      return -2;
    case 'b':
      return -1;
    case '#':
      return 1;
    case '##':
      return 2;
    default:
      return 0;
  }
}

int? _parseMeasureNumber(String? raw) {
  if (raw == null) {
    return null;
  }
  final match = RegExp(r'^(\d+)').firstMatch(raw.trim());
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1)!);
}

bool _noteMatchesPitch(XmlElement note, _ParsedPitch target) {
  final parsed = _extractPitch(note);
  if (parsed == null) {
    return false;
  }
  return parsed.step == target.step &&
      parsed.alter == target.alter &&
      parsed.octave == target.octave;
}

_ParsedPitch? _extractPitch(XmlElement note) {
  final pitchElement = note.getElement('pitch');
  if (pitchElement == null) {
    return null;
  }

  final step = pitchElement.getElement('step')?.innerText;
  final octaveString = pitchElement.getElement('octave')?.innerText;
  if (step == null || octaveString == null) {
    return null;
  }

  final alterString = pitchElement.getElement('alter')?.innerText;
  final alter = alterString == null ? 0 : int.tryParse(alterString.trim()) ?? 0;
  final octave = int.tryParse(octaveString.trim());
  if (octave == null) {
    return null;
  }

  return _ParsedPitch(
    step: step.trim().toUpperCase(),
    alter: alter,
    octave: octave,
  );
}
