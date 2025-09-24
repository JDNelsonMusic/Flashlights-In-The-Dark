import 'package:flutter/services.dart' show rootBundle;
import 'package:xml/xml.dart';

const String _kScoreAssetPath = 'assets/FlashlightsInTheDark_SingerScore23.musicxml';

const Set<String> _kLightChorusPartIds = {
  'P4',
  'P5',
  'P6',
  'P7',
  'P8',
  'P9',
  'P10',
  'P11',
  'P12',
};

const Map<String, String> _kPartIdToHexColor = {
  'P4': '#0800F0', // Blue
  'P5': '#F00800', // Red
  'P6': '#29F000', // Green
  'P7': '#6E00F0', // Purple
  'P8': '#F0AD00', // Yellow
  'P9': '#FFB8D9', // Pink
  'P10': '#F05100', // Orange
  'P11': '#FF00D7', // Magenta
  'P12': '#9EE4FF', // Cyan
};

String? _cachedTrimmedXml;

Future<String> loadTrimmedMusicXML() async {
  if (_cachedTrimmedXml != null) {
    return _cachedTrimmedXml!;
  }

  final raw = await rootBundle.loadString(_kScoreAssetPath);
  final document = XmlDocument.parse(raw);

  final root = document.rootElement;
  final partList = root.getElement('part-list');
  if (partList != null) {
    final removable = partList.children
        .whereType<XmlElement>()
        .where(
          (element) =>
              element.name.local == 'score-part' &&
              !_kLightChorusPartIds.contains(element.getAttribute('id')),
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
            !_kLightChorusPartIds.contains(element.getAttribute('id')),
      )
      .toList(growable: false);
  for (final part in removableParts) {
    part.parent?.children.remove(part);
  }

  for (final part in root.children.whereType<XmlElement>()) {
    if (part.name.local != 'part') {
      continue;
    }
    final partId = part.getAttribute('id');
    final hexColor = _kPartIdToHexColor[partId];
    if (hexColor == null) {
      continue;
    }
    for (final note in part.findAllElements('note')) {
      if (note.getAttribute('color') == null) {
        note.setAttribute('color', hexColor);
      }
    }
  }

  _cachedTrimmedXml = document.toXmlString(pretty: false);
  return _cachedTrimmedXml!;
}
