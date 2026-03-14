# Electronics Sync Reference

Manual timing anchors in this file are authoritative project assumptions for aligning exported electronics audio against score positions when deriving the `192` event recipes.

Use these anchors against the official trigger positions documented in `docs/official_trigger_positions.md` and stored in `Flashlights-ITD_EventRecipes_4_2026_0309/official_trigger_positions.csv`.

## Stereo Sum Anchor

- Source file: `audio/protools-exports/electronics/2026_0314_FlashlightsInTheDark_Electronics-StereoSum_7.mp3`
- Reference point: measure `2`, beat `1`
- Absolute time in file: `11.912` seconds (`00:11.912`)
- Interpretation: treat `00:11.912` as the point where measure `2` beat `1` lands in this stereo-sum export when calculating or validating clip offsets

## Notes

- This is a manually asserted sync reference, not a value derived from the generated MusicXML timing report.
- If a later export supersedes `2026_0314_FlashlightsInTheDark_Electronics-StereoSum_7.mp3`, add a new anchor here rather than silently reusing this timestamp for a different file.
