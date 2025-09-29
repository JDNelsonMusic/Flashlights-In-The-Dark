import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:xml/xml.dart';

import 'package:flashlights_client/model/event_recipe.dart';

const String _kScoreAssetPath =
    'assets/FlashlightsInTheDark_SingerScore23.musicxml';

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

class TrimmedMusicXmlResult {
  const TrimmedMusicXmlResult({
    required this.xml,
    required this.windowStart,
    required this.windowEnd,
    required this.measureCount,
    required this.sourceCenter,
  });

  final String xml;
  final int windowStart;
  final int windowEnd;
  final int measureCount;
  final int? sourceCenter;

  Map<String, dynamic> toMetaJson() => <String, dynamic>{
    'sourceWindowStart': windowStart,
    'sourceWindowEnd': windowEnd,
    'sourceCenter': sourceCenter,
    'measureCount': measureCount,
  };
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

final Map<PrimerColor?, String> _cachedTrimmedXmlByColor = {};

const Set<String> _kRemovableRootElements = {
  'credit',
  'identification',
  'defaults',
  'work',
  'movement-number',
  'movement-title',
};
const Set<String> _kAllowedMeasureChildren = {
  'attributes',
  'note',
  'backup',
  'forward',
  'barline',
  'print',
};

const Set<String> _kAllowedNoteChildren = {
  'pitch',
  'duration',
  'rest',
  'type',
  'voice',
  'time-modification',
  'stem',
  'dot',
  'chord',
  'grace',
  'tie',
  'beam',
};

class _ParsedPitch {
  const _ParsedPitch({
    required this.step,
    required this.alter,
    required this.octave,
  });

  final String step;
  final int alter;
  final int octave;
}

Future<TrimmedMusicXmlResult> loadTrimmedMusicXML({
  PrimerColor? forColor,
  int? highlightMeasure,
  String? highlightNote,
}) async {
  final baseXml = await _loadBaseTrimmedMusicXML(forColor: forColor);
  final document = XmlDocument.parse(baseXml);
  document.children.removeWhere((node) => node is XmlDoctype);

  final clipPlan = _resolveWindowPlan(document, center: highlightMeasure);

  final clipResult = _clipDocumentToRange(
    document,
    start: clipPlan.start,
    end: clipPlan.end,
  );

  final parsedPitch =
      highlightNote == null ? null : _parseNoteLabel(highlightNote);
  if (highlightMeasure != null && parsedPitch != null) {
    _applyPrimerHighlight(
      document,
      measureNumber: highlightMeasure,
      pitch: parsedPitch,
    );
  }

  _pruneToCoreNotation(document);

  final measureCount = _reindexMeasures(document);
  final resolvedMeasureCount =
      measureCount == 0 ? math.max(clipResult.count, 1) : measureCount;

  final xml = document.toXmlString(pretty: false);
  return TrimmedMusicXmlResult(
    xml: xml,
    windowStart: clipResult.start,
    windowEnd: clipResult.end,
    measureCount: resolvedMeasureCount,
    sourceCenter: highlightMeasure,
  );
}

Future<String> _loadBaseTrimmedMusicXML({PrimerColor? forColor}) async {
  final cached = _cachedTrimmedXmlByColor[forColor];
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

    partList.children.removeWhere(
      (node) => node is XmlElement && node.name.local == 'part-group',
    );
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

  root.children.removeWhere(
    (node) =>
        node is XmlElement && _kRemovableRootElements.contains(node.name.local),
  );

  _normaliseNoteColors(root: root, allowedPartIds: allowedPartIds);

  final xml = document.toXmlString(pretty: false);
  _cachedTrimmedXmlByColor[forColor] = xml;
  return xml;
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

class _WindowPlan {
  const _WindowPlan({required this.start, required this.end});

  final int start;
  final int end;
}

class _ClipResult {
  const _ClipResult({
    required this.start,
    required this.end,
    required this.count,
  });

  final int start;
  final int end;
  final int count;
}

_WindowPlan _resolveWindowPlan(XmlDocument document, {int? center}) {
  final numbers = _collectMeasureNumbers(document);
  if (numbers.isEmpty) {
    return const _WindowPlan(start: 1, end: 1);
  }

  final first = numbers.first;
  final last = numbers.last;

  var windowStart = center == null ? first : math.max(first, center - 1);
  var windowEnd =
      center == null ? math.min(first + 2, last) : math.min(last, center + 1);

  while (windowEnd - windowStart < 2 && windowStart > first) {
    windowStart -= 1;
  }
  while (windowEnd - windowStart < 2 && windowEnd < last) {
    windowEnd += 1;
  }

  windowStart = math.max(first, math.min(windowStart, last));
  windowEnd = math.max(windowStart, math.min(windowEnd, last));

  return _WindowPlan(start: windowStart, end: windowEnd);
}

_ClipResult _clipDocumentToRange(
  XmlDocument document, {
  required int start,
  required int end,
}) {
  int? firstKept;
  int? lastKept;
  var maxKept = 0;

  for (final part in document.rootElement.findElements('part')) {
    final measures = part.findElements('measure').toList(growable: false);
    XmlElement? lastAttributesBeforeWindow;
    final toRemove = <XmlElement>[];

    for (final measure in measures) {
      final number = _parseMeasureNumber(measure.getAttribute('number'));
      final attributesElement = measure.getElement('attributes');

      if (number != null && attributesElement != null) {
        if (number < start ||
            (number == start && lastAttributesBeforeWindow == null)) {
          lastAttributesBeforeWindow = _cloneAttributesElement(
            attributesElement,
          );
        }
      }

      if (number == null) {
        toRemove.add(measure);
        continue;
      }
      if (number < start) {
        toRemove.add(measure);
        continue;
      }
      if (number > end) {
        toRemove.add(measure);
        continue;
      }

      firstKept ??= number;
      lastKept = number;
    }

    for (final remove in toRemove) {
      remove.parent?.children.remove(remove);
    }

    final keptMeasures = part.findElements('measure').toList(growable: false);
    if (keptMeasures.isEmpty) {
      continue;
    }

    maxKept = math.max(maxKept, keptMeasures.length);

    final firstMeasure = keptMeasures.first;
    XmlElement? firstAttributes = firstMeasure.getElement('attributes');

    if (lastAttributesBeforeWindow != null) {
      if (firstAttributes == null) {
        final clonedAttributes = _cloneAttributesElement(
          lastAttributesBeforeWindow,
        );
        firstMeasure.children.insert(0, clonedAttributes);
        firstAttributes = clonedAttributes;
      } else {
        _mergeAttributes(firstAttributes, lastAttributesBeforeWindow);
      }
    }
  }

  final resolvedFirst = firstKept ?? start;
  final resolvedLast = lastKept ?? end;

  if (maxKept == 0) {
    maxKept = math.max(1, resolvedLast - resolvedFirst + 1);
  }

  return _ClipResult(start: resolvedFirst, end: resolvedLast, count: maxKept);
}

XmlElement _cloneAttributesElement(XmlElement source) {
  return source.copy();
}

void _mergeAttributes(XmlElement target, XmlElement fallback) {
  _ensureAttributeChild(target, fallback, 'divisions');
  _ensureAttributeChild(target, fallback, 'key');
  _ensureAttributeChild(target, fallback, 'time');
  _ensureAttributeChild(target, fallback, 'clef', matchNumber: true);
}

void _ensureAttributeChild(
  XmlElement target,
  XmlElement fallback,
  String localName, {
  bool matchNumber = false,
}) {
  final fallbackElements = fallback.children
      .whereType<XmlElement>()
      .where((element) => element.name.local == localName)
      .toList(growable: false);
  if (fallbackElements.isEmpty) {
    return;
  }

  if (!matchNumber) {
    final hasTarget = target.children.whereType<XmlElement>().any(
      (element) => element.name.local == localName,
    );
    if (hasTarget) {
      return;
    }
    for (final fallbackElement in fallbackElements) {
      _insertAttributeElement(target, _cloneChildElement(fallbackElement));
    }
    return;
  }

  for (final fallbackElement in fallbackElements) {
    final fallbackNumber = fallbackElement.getAttribute('number');
    final hasMatch = target.children.whereType<XmlElement>().any((element) {
      if (element.name.local != localName) {
        return false;
      }
      final existingNumber = element.getAttribute('number');
      return existingNumber == fallbackNumber;
    });
    if (!hasMatch) {
      _insertAttributeElement(target, _cloneChildElement(fallbackElement));
    }
  }
}

int _attributeOrderIndex(String localName) {
  switch (localName) {
    case 'divisions':
      return 0;
    case 'key':
      return 1;
    case 'time':
      return 2;
    case 'clef':
      return 3;
    default:
      return 4;
  }
}

XmlElement _cloneChildElement(XmlElement element) {
  return element.copy();
}

void _insertAttributeElement(XmlElement target, XmlElement element) {
  final order = _attributeOrderIndex(element.name.local);
  var insertIndex = target.children.length;
  for (var i = 0; i < target.children.length; i += 1) {
    final child = target.children[i];
    if (child is! XmlElement) {
      continue;
    }
    final childOrder = _attributeOrderIndex(child.name.local);
    if (order < childOrder) {
      insertIndex = i;
      break;
    }
  }
  target.children.insert(insertIndex, element);
}

int _reindexMeasures(XmlDocument document) {
  var maxCount = 0;
  for (final part in document.rootElement.findElements('part')) {
    final measures = part.findElements('measure').toList(growable: false);
    maxCount = math.max(maxCount, measures.length);
    for (var i = 0; i < measures.length; i++) {
      final measure = measures[i];
      final originalNumber =
          _parseMeasureNumber(measure.getAttribute('data-source-measure')) ??
          _parseMeasureNumber(measure.getAttribute('number'));

      measure.attributes.removeWhere(
        (attribute) => attribute.name.local == 'data-source-measure',
      );
      if (originalNumber != null) {
        measure.attributes.add(
          XmlAttribute(XmlName('data-source-measure'), '$originalNumber'),
        );
      }

      final numberAttribute = measure.getAttributeNode('number');
      if (numberAttribute != null) {
        numberAttribute.value = '${i + 1}';
      } else {
        measure.attributes.add(XmlAttribute(XmlName('number'), '${i + 1}'));
      }
    }
  }
  return maxCount;
}

List<int> _collectMeasureNumbers(XmlDocument document) {
  final numbers = <int>{};
  for (final part in document.rootElement.findElements('part')) {
    for (final measure in part.findElements('measure')) {
      final number = _parseMeasureNumber(measure.getAttribute('number'));
      if (number != null) {
        numbers.add(number);
      }
    }
  }
  final ordered = numbers.toList()..sort();
  return ordered;
}

void _pruneToCoreNotation(XmlDocument document) {
  for (final measure in document.findElements('measure')) {
    measure.children.removeWhere((node) {
      if (node is! XmlElement) {
        return false;
      }
      return !_kAllowedMeasureChildren.contains(node.name.local);
    });
    for (final note in measure.findElements('note')) {
      note.children.removeWhere((node) {
        if (node is! XmlElement) {
          return false;
        }
        return !_kAllowedNoteChildren.contains(node.name.local);
      });
    }
  }
}

void _applyPrimerHighlight(
  XmlDocument document, {
  required int measureNumber,
  required _ParsedPitch pitch,
}) {
  final root = document.rootElement;
  final targetMeasures = <int>{measureNumber};
  if (measureNumber > 1) {
    targetMeasures.add(measureNumber - 1);
  }
  targetMeasures.add(measureNumber + 1);
  for (final part in root.findElements('part')) {
    for (final measure in part.findElements('measure')) {
      final parsedNumber = _parseMeasureNumber(measure.getAttribute('number'));
      if (parsedNumber == null || !targetMeasures.contains(parsedNumber)) {
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

  _clearStemHighlight(note);
}

void _removeHighlightAttributes(XmlElement note) {
  note.attributes.removeWhere(
    (attribute) => attribute.name.local == _kHighlightDataAttribute,
  );
}

void _clearStemHighlight(XmlElement note) {
  for (final stem in note.findElements('stem')) {
    stem.attributes.removeWhere((attribute) {
      final name = attribute.name.local;
      if (name == _kHighlightDataAttribute) {
        return true;
      }
      if (name == 'color') {
        return true;
      }
      return false;
    });
  }
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
