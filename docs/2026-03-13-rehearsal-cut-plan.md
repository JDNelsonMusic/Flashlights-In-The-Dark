# 2026-03-13 Rehearsal Cut Plan

Status: current working cut note from director/composer correspondence on March 13, 2026

Purpose: capture the currently agreed rehearsal cut in one place, with enough score and event-map context to drive score edits, recipe regeneration, Pro Tools work, and choir communication.

## Agreed Immediate Rehearsal Cut

Choir-facing wording from the correspondence:

> Measures 1-37 (shadow chorus holding through 38) -hold for 4 more measures of twinkling noises and lights -- Chorus enters at 104

Working interpretation now implemented in the repo:

- Keep original measures `1-37`.
- Keep original measures `38-41` as the `4`-measure bridge window.
- Relabel those four bridge measures in the cut score as:
  - `38`
  - `38.2`
  - `38.3`
  - `38.4`
- Rewrite those bridge measures as singer rests in the tour-cut score.
- Re-enter with the chorus at original measure `104`.
- For the current rehearsal/tour version, this bypasses original measures `42-103`.

## Current Event-Map Anchors

These timings come from the current uncut timeline in `docs/protools-housekeeping/event_timeline.json`. They are orientation anchors only. If the cut is implemented, the surviving events will move earlier in performance time and the timing report must be regenerated.

| Function | Current event(s) | Current measure(s) | Current time in uncut version |
| --- | --- | --- | --- |
| end of retained opening section | `35` | `37` | `1:31.152` |
| shadow-chorus hold zone | `36-39` | `38` | `1:32.402` to `1:34.069` |
| four-measure bridge zone | `40-50` | `39-42` | `1:34.902` to `1:47.819` |
| pre-re-entry tail in current full version | `152-155` | `103` | `4:46.569` to `4:47.819` |
| chorus re-entry target | `156` | `104` | `4:49.069` |

Event detail around the cut boundary:

- Event `35`: measure `37`, position `4+1/2-of-4`, onset `91.151961s`
- Events `36-39`: measure `38`, onset range `92.401960s` to `94.068627s`
- Events `40-50`: measures `39-42`, onset range `94.901961s` to `107.818628s`
- Events `152-155`: measure `103`, onset range `286.568627s` to `287.818627s`
- Event `156`: measure `104`, position `1-of-4`, onset `289.068627s`

## Level-Up Restoration Sequence

The correspondence also established a phased expansion path after the immediate cut is working:

1. Start with the rehearsal cut above.
2. Add the rest of page `6`.
3. Then add page `3`.
4. Then add pages `4` and `5`.

This means the current plan is not just a one-off cut. It is a staged reintroduction strategy, so future edits should preserve a path back toward the longer form instead of deleting middle material carelessly.

## Additional Musical Development Note

Jon noted a possible enhancement for the bridge:

- mix in a synthesized version of approximately measures `100-104`
- let it grow during the four measures where the choir rests
- use it to prepare the returning harmony before the measure `104` entrance

This should be treated as an optional bridge-development idea, not yet as canonical structure.

## Implementation Implications

For this repo, the cut affects four layers:

### Score and recipe layer

- The structural change is now implemented as:
  `1-37`, then cut-score bridge measures `38 / 38.2 / 38.3 / 38.4`, then original measure `104`.
- The current cut score file is `Flashlights-ITD_EventRecipes_4_2026_0309/FlashlightsInTheDark_v32_TourCut.musicxml`.
- After the score is updated, regenerate the recipe bundle before editing downstream copies by hand.

### Runtime app layer

- Update `Flashlights-ITD_EventRecipes_4_2026_0309/event_recipes.json`.
- Propagate the regenerated bundle to:
  - `FlashlightsInTheDark_MacOS/Resources/event_recipes.json`
  - `flashlights_client/assets/event_recipes.json`
- If the MusicXML filename or version changes, also update:
  - `flashlights_client/assets/FlashlightsInTheDark_v32_TourCut.musicxml`
  - `flashlights_client/lib/utils/music_xml_utils.dart`
  - `flashlights_client/pubspec.yaml`

### Pro Tools / audio layer

- Preserve the opening through measure `38`.
- Build or refine the `4`-measure twinkling/noise/light bridge.
- Retarget the re-entry so the measure `104` entrance feels intentional, not like a hard splice.
- Keep any removed middle material recoverable so the phased restoration plan remains possible.

### Rehearsal communication layer

The current choir-facing instruction should stay simple:

> Measures 1-37, shadow chorus holding through 38, then 4 measures of twinkling noises and lights, chorus enters at 104.

## Recommended Next Actions

1. Mark the exact cut and bridge plan in the score source.
2. Decide whether the bridge uses existing measures `39-42`, newly composed material, or a hybrid.
3. Regenerate the event recipe bundle and timing outputs.
4. Rebuild the corresponding transition in Pro Tools.
5. Smoke-test the updated score and recipe copies in the macOS and Flutter apps.
