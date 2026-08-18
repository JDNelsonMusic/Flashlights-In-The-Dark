# PROJECT_STATE

Last refreshed: August 18, 2026

This file is the workspace source-of-truth map for the current repository state. It is meant to answer two questions quickly:

1. What is currently canonical?
2. If I change the piece structure, what else do I have to touch?

## Current Canonical State

- Editorial working text for the Fall 2026 edition:
  `Documentation/Project-Management/FALL_2026_WORKING_TEXT.md`
- Exact 88-cue captured text source and public reading display:
  `Communiti/components/ToolsForArtists/flashlightsAssemblyTwinPoem.js` and
  `https://simphoni.ai/flashlights/twin-poem`

- Musical structure and cue timing source:
  `Engraving/Scores/FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml`
- Active show profile:
  `full_version` in `Show-Control/Show-Profiles/show_profiles.json`
- Canonical cue bundle:
  `Show-Control/Event-Recipes/Flashlights-ITD_EventRecipes_4_2026_0309/event_recipes.json`
- Runtime cue bundle copies:
  `Software/Conductor-MacOS/FlashlightsInTheDark_MacOS/Resources/event_recipes.json`
  `Software/Singer-Client/assets/event_recipes.json`
- Canonical Pro Tools working-session candidate:
  `DAW-Production/ProTools-Session/2025_0727_FlashlightsInTheDark22_MappingPrimerTones_3.r.ptx`
- Primer asset sets currently in sync:
  `Software/Conductor-MacOS/FlashlightsInTheDark_MacOS/Audio/primerTones/`
  `Software/Singer-Client/available-sounds/primerTones/`
- Historical director/composer rehearsal-cut note:
  `Documentation/Project-Management/2026-03-13-rehearsal-cut-plan.md`
- Housekeeping and timing reports:
  `DAW-Production/Audits/`

Verified current facts from the generated reports:

- The active runtime trigger bundle currently contains `12` full-version macro trigger events.
- The recipe copies in the recipe folder, macOS app, and Flutter app are byte-identical.
- The primer MP3s in the macOS app and Flutter app are byte-identical with `98` matched files.
- The bundled full-version trigger electronics currently has `36` rendered clips: `12` triggers x `3` choir-family variants.
- Restored middle trigger points are `6` at `M46 beat3`, `7` at `M63 beat3`, `8` at `M78 beat1`, `9` at `M89 beat1`, and `10` at `M98 beat1`.
- Encoded tempo changes occur at measure `1` (`102 BPM`) and measure `30` (`72 BPM`).
- Current timeline report: first trigger `0:00.000`, last trigger `5:24.069`, encoded score end `6:58.235`.

## Workspace Map

| Path | Role | Status |
| --- | --- | --- |
| `README.md` | project overview and contributor-facing setup | active |
| `Documentation/Project-Management/` | active planning, readiness, review, and state docs | active coordination layer |
| `Software/Conductor-MacOS/FlashlightsInTheDark_MacOS/` | macOS conductor console | core runtime target |
| `Software/Singer-Client/` | Flutter singer client | core runtime target |
| `DAW-Production/ProTools-Session/` | Pro Tools sessions, backups, raw and rendered audio | core composer/audio workspace |
| `Show-Control/Event-Recipes/Flashlights-ITD_EventRecipes_4_2026_0309/` | current score + recipe generation output set | current canonical full-version score/recipe folder |
| `Show-Control/Event-Recipes/Flashlights-ITD_EventRecipes_3_2025_0921/` | older recipe + score generation | legacy reference, not current source-of-truth |
| `Operations/Scripts/` | operational and generation scripts | active |
| `DAW-Production/Audits/` | generated audit + timeline outputs for the Pro Tools work | active orientation layer |
| `Visual-Production/Reference-Images/` | official trigger-score photos and visual reference graphics | active reference layer |
| `Engraving/Score-Study/` | collected score-study submissions and archive zip | secondary reference, not on immediate runtime path |
| `Operations/Light-Chorus/` | MIDI-to-spreadsheet helper app | active support tooling |
| `Operations/Tools/light_chorus_gui.py` | Light Chorus spreadsheet-builder entrypoint | active support tooling |
| `Operations/Tools/legacy/` | older backup/prototype Python control utilities | legacy support tooling |
| `Documentation/` | OSC schema, validation, deployment notes | active support docs |
| `Operations/Fastlane/` | iOS/TestFlight support | active but not on the cut-critical path |
| `Web-Surfaces/Communiti-Flashlights/` | public resource hub and reusable React package | publish/deploy only after rights review |

## Core Data Flow

For the currently wired concert path, the project flows like this:

1. `MusicXML score`
2. `event recipe generation`
3. `event_recipes.json`
4. `macOS conductor + Flutter client runtime assets`
5. `rehearsal/performance triggering`

The practical implication is:

- structural changes should start in the score and recipe layer
- editorial text changes should start from the documented Fall 2026 working
  text and be deliberately engraved before any downstream regeneration
- not in the UI
- not in random copied JSON files
- not in Pro Tools first

Pro Tools is a parallel audio-production layer, but the conductor/client event logic is now largely data-driven from `event_recipes.json`.

The `measure` and `position` attached to each event should now be read as the official trigger point from the annotated trigger-score photos, not as the sung-note onset.

## Source-Of-Truth Matrix

| Domain | Canonical source | Downstream copies / consumers | Notes |
| --- | --- | --- | --- |
| Fall 2026 editorial text | `Documentation/Project-Management/FALL_2026_WORKING_TEXT.md` and the 88-cue Communiti Assembly capture | Twin Poem reading page; future engraving/rehearsal copy | Current working text; it does not automatically replace MusicXML or generated runtime assets |
| Score timing and measure structure | `Engraving/Scores/FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml` | `Software/Singer-Client/assets/FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml`, `DAW-Production/Audits/event_timeline.*` | Full-version profile source for December 2026 planning |
| Macro trigger positions | `Engraving/Score-Study/full_version_trigger_points.csv` | `Operations/Scripts/build_electronics_trigger_point_assets.py`, runtime JSON `measure` / `position` fields | Twelve conductor trigger points for the full-length show |
| 192-event trigger positions | `Show-Control/Event-Recipes/Flashlights-ITD_EventRecipes_4_2026_0309/official_trigger_positions.csv` | `Operations/Scripts/generate_event_recipes_v4.py`, recipe spreadsheet rows | Light-chorus reference table; not the active macro trigger runtime bundle |
| Event recipe bundle | `Show-Control/Event-Recipes/Flashlights-ITD_EventRecipes_4_2026_0309/event_recipes.json` | `Software/Conductor-MacOS/FlashlightsInTheDark_MacOS/Resources/event_recipes.json`, `Software/Singer-Client/assets/event_recipes.json` | Copies are byte-identical and carry full-version trigger metadata |
| Active profile manifest | `Show-Control/Show-Profiles/show_profiles.json` | `Software/Conductor-MacOS/FlashlightsInTheDark_MacOS/Resources/show_profiles.json`, `Software/Singer-Client/assets/show_profiles.json` | `full_version` is active and runtime-ready; `tour_cut` is archived/reference |
| Electronics trigger asset generation | `Operations/Scripts/build_electronics_trigger_point_assets.py --active-profile full_version` | `DAW-Production/Audits/electronics_trigger_assets.json`, `Software/Singer-Client/available-sounds/electronics-trigger-clips/` | Renders 12 x 3 full-version trigger clips from the full electronics master plus primer stems |
| Light-show generation/injection | `Operations/Scripts/build_trigger_point_light_show.py --active-profile full_version` | `Engraving/Score-Study/twelve_trigger_light_show.json`, runtime event `lighting` fields | Restores middle-section lighting between M36 and M104 |
| macOS cue UI | `Software/Conductor-MacOS/FlashlightsInTheDark_MacOS/View/EventTriggerStrip.swift` | consumes decoded event recipes | Event count is dynamic |
| Flutter cue/practice model | `Software/Singer-Client/lib/model/event_recipe.dart` | consumes decoded event recipes | Event count is dynamic |
| Flutter asset registration | `Software/Singer-Client/pubspec.yaml` | bundles runtime JSON and electronics trigger folders | Must stay aligned with renamed or added assets |
| Pro Tools working session | `DAW-Production/ProTools-Session/2025_0727_FlashlightsInTheDark22_MappingPrimerTones_3.r.ptx` | composer DAW workflow | Recommendation only; confirm in Pro Tools |
| Pro Tools audit / cue timing reports | `DAW-Production/Audits/` | composer orientation and cleanup passes | Generated, safe to regenerate |

## If You Reshape The Full Version Again

If you add, remove, or relocate a large span after this full-version restoration, the likely blast radius is:

1. `MusicXML score source`
   You will change measure structure, surviving notes, and possibly measure numbering after the cut.
2. `event recipe generation`
   The event list, event count, measure positions, and sample assignments will change.
3. `runtime recipe JSON copies`
   Both the macOS and Flutter apps must receive the updated bundle.
4. `Flutter score-practice asset`
   If the new score lives under a new filename or version, update both the asset file and the hardcoded path in `music_xml_utils.dart`.
5. `Electronics trigger clips and Pro Tools session`
   The session arrangement, stems, transitions, and possibly primer/support sounds will need parallel edits.
6. `documentation and public text`
   The repo currently still says "nine-minute" or "~9 minutes" in multiple places.

What likely does **not** require deep code surgery:

- the macOS event strip UI
- the Flutter event recipe parsing logic
- the event count itself

Those layers appear to consume the event bundle dynamically. The "192 events" references that still exist are currently comments and metadata, not core logic constraints.

## Full-Version Reshape Working Order

Do this in order:

1. Decide the change in score terms first.
   Record it as start/end measures and nearest macro trigger IDs.
2. Change the score source.
   Do not start by hand-editing copied JSON bundles.
3. Regenerate the recipe bundle and timing reports.
   This gives you the new event count and the new cue-time map immediately.
4. Update the runtime copies.
   macOS recipe JSON, Flutter recipe JSON, and Flutter MusicXML asset.
5. Only then do the Pro Tools cut.
   Use the regenerated event timeline as the target shape.
6. Smoke-test the conductor and mobile client.
7. Clean up duration text and stale comments.

## Recommended 24-Hour Triage

If the goal is "get the full piece substantially pulled together in the next day", the best sequence is:

1. Review the restored 12-trigger arc in `Engraving/Score-Study/twelve_trigger_light_show.json`.
2. Audition the newly rendered `electronics-trigger-clips` on representative phones.
3. Validate the middle-section lighting at triggers `5-10` in a dark room with several devices.
4. Reconcile Pro Tools against `DAW-Production/Audits/event_timeline_events.csv`.
5. Run a minimal end-to-end test: Mac event strip, phone audio, phone lighting, and ACK/resend behavior.

## Fast Recovery Checklist

If coming back cold after months away, open these first:

1. `Documentation/Project-Management/PROJECT_STATE.md`
2. `Documentation/Project-Management/2026-03-13-rehearsal-cut-plan.md`
3. `Documentation/Project-Management/composermap.md`
4. `DAW-Production/Audits/session_audit.md`
5. `DAW-Production/Audits/event_timeline.md`
6. `Operations/Scripts/generate_event_recipes_v4.py`
7. `Engraving/Scores/FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml`
8. `Show-Control/Event-Recipes/Flashlights-ITD_EventRecipes_4_2026_0309/event_recipes.json`
9. `Engraving/Score-Study/twelve_trigger_light_show.json`
10. `Software/Singer-Client/pubspec.yaml`
11. `DAW-Production/ProTools-Session/2025_0727_FlashlightsInTheDark22_MappingPrimerTones_3.r.ptx`

## Regenerate Orientation Data

From the repo root:

```bash
python3 Operations/Scripts/audit_protools_session.py
python3 Operations/Scripts/build_show_runtime.py --active-profile full_version
python3 Operations/Scripts/build_protools_event_timeline.py --score-xml Engraving/Scores/FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml
```

## Do Not Burn Time On These First

Until the cut shape is stable, avoid spending early hours on:

- renaming every odd audio file in the Pro Tools folder
- polishing UI details
- cleaning every legacy backup
- rewriting overview docs
- app-store or board-facing text updates

First stabilize the score, event bundle, and Pro Tools structure. Everything else is downstream.
