# Event Timeline And Integration Report

Generated: `2026-03-13T09:23:16+00:00`
Recipe source: `Flashlights-ITD_EventRecipes_4_2026_0309/event_recipes.json`
Score source: `Flashlights-ITD_EventRecipes_4_2026_0309/FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml`

## Timeline Snapshot

- Events: `192`
- Clip rows: `1428`
- Long events: `14`
- First event: `0:00.000`
- Last event: `6:29.902`
- Score end: `6:58.235`

## Tempo Map

- Measure `1` starts at `0:00.000` with `102.0` BPM in `4/4`
- Measure `30` starts at `1:08.235` with `72.0` BPM in `4/4`

## Timing Caveats

- Performance-time onsets are exact with respect to the encoded MusicXML tempo and meter map.
- The score contains explicit tempo changes at measures 1 (102 BPM) and 30 (72 BPM), with no later encoded tempo changes.
- Measures 115 and 130 contain 'articulate freely in aleatoric style'; events in and after that late section should be human-validated if absolute seconds matter in performance.
- Clip end times use the currently bundled primer asset durations, not clip-edge data from the PTX files.

## Integration Checks

- Event recipe copies identical: `True`
- Primer asset counts: macOS `98`, Flutter `98`
- Referenced samples missing in macOS assets: `0`
- Referenced samples missing in Flutter assets: `0`
- Primer asset hash mismatches across macOS/Flutter: `0`

## Outputs

- `event_timeline.json`
- `event_timeline_events.csv`
- `event_timeline_clips.csv`

