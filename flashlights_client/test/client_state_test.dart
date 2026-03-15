import 'package:flutter_test/flutter_test.dart';

import 'package:flashlights_client/model/client_state.dart';
import 'package:flashlights_client/model/event_recipe.dart';

void main() {
  group('ClientState.electronicsForSlot', () {
    test('prefers part-specific electronics over choir-family fallback', () {
      final state = ClientState();
      final familyAssignment = ElectronicsAssignment(
        sample: 'available-sounds/electronics-trigger-clips/soprano/family.mp3',
        channelMode: 'left',
        durationMs: 8000,
      );
      final partAssignment = ElectronicsAssignment(
        sample:
            'available-sounds/electronics-trigger-clips/part-specific/soprano-l2/trigger-08.mp3',
        channelMode: 'part_track',
        durationMs: 3333.333,
      );
      final event = EventRecipe(
        id: 8,
        measure: 38,
        measureToken: '38.3',
        scoreMeasureOrdinal: 40,
        position: 'beat1',
        scoreLabel: 'M38.3, beat1',
        primerAssignments: const <PrimerColor, PrimerAssignment>{},
        electronicsAssignments: <ChoirFamily, ElectronicsAssignment>{
          ChoirFamily.soprano: familyAssignment,
        },
        electronicsByPart: <String, ElectronicsAssignment>{
          LightChorusPart.sopranoL2.recipeKey: partAssignment,
        },
        lighting: null,
      );

      expect(state.electronicsForSlot(event, 12)?.sample, partAssignment.sample);
      expect(state.electronicsForSlot(event, 16)?.sample, familyAssignment.sample);
    });
  });
}
