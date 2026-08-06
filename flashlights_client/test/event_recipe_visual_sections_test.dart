import 'package:flutter_test/flutter_test.dart';

import 'package:flashlights_client/model/event_recipe.dart';

void main() {
  test('parses optional visual section metadata', () {
    final event = EventRecipe.fromJson(<String, dynamic>{
      'id': 2,
      'visualSectionIds': <int>[2, 3, 4],
      'visualSectionWindows': <Map<String, dynamic>>[
        <String, dynamic>{
          'sectionId': 2,
          'key': 'forte_shimmer',
          'label': 'Forte shimmer',
          'startAtMs': 0,
          'endAtMs': 1000.5,
          'durationMs': 1000.5,
        },
      ],
    });

    expect(event.visualSectionIds, <int>[2, 3, 4]);
    expect(event.visualSectionWindows, hasLength(1));
    expect(event.visualSectionWindows.single.sectionId, 2);
    expect(event.visualSectionWindows.single.key, 'forte_shimmer');
    expect(event.visualSectionWindows.single.endAtMs, 1000.5);
  });

  test('defaults visual section metadata for existing recipes', () {
    final event = EventRecipe.fromJson(<String, dynamic>{'id': 1});

    expect(event.visualSectionIds, isEmpty);
    expect(event.visualSectionWindows, isEmpty);
  });
}
