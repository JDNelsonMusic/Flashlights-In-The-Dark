# composermap

Last refreshed: March 13, 2026

This file is meant to help you reorient fast as the composer/technical owner of the piece after time away.

It is not a contributor guide. It is a "where am I, what is alive, and what do I touch first if I need to reshape the piece tonight?" map.

## If You Only Have 10 Minutes

Read these in order:

1. `docs/project-management/PROJECT_STATE.md`
2. `docs/2026-03-13-rehearsal-cut-plan.md`
3. `docs/protools-housekeeping/event_timeline.md`
4. `docs/protools-housekeeping/session_audit.md`
5. `Flashlights-ITD_EventRecipes_4_2026_0309/FlashlightsInTheDark_v32_TourCut.musicxml`
6. `FlashlightsInTheDark_Protools-Session/2025_0727_FlashlightsInTheDark22_MappingPrimerTones_3.r.ptx`

Then answer one question before doing anything else:

`What exact version of the 38 -> bridge -> 104 handoff am I implementing?`

## Current Agreed Rehearsal Cut

As of March 13, 2026, the currently agreed immediate cut to communicate to the choir is captured in:

`docs/2026-03-13-rehearsal-cut-plan.md`

Short version:

- measures `1-37` (shadow chorus holds through `38`)
- `4` measures of twinkling noises and lights
- chorus enters at `104`

Repo-level interpretation now implemented:

- preserve original measures `1-37`
- keep original measures `38-41` as the `4`-measure bridge window
- relabel those four measures as `38 / 38.2 / 38.3 / 38.4`
- rewrite those bridge measures as singer rests in the tour-cut score
- bypass original measures `42-103`
- preserve enough structure that the phased restoration plan can add material back later

### Current Cut Anchors

Use these as the live orientation points for the current uncut event map:

| Function | Event(s) | Measure(s) | Current uncut time |
| --- | --- | --- | --- |
| end of retained opening | `35` | `37` | `1:31.152` |
| shadow-chorus hold | `36-39` | `38` | `1:32.402` to `1:34.069` |
| bridge-sized twinkling zone | `40-50` | `39-42` | `1:34.902` to `1:47.819` |
| pre-return tail | `152-155` | `103` | `4:46.569` to `4:47.819` |
| chorus return target | `156` | `104` | `4:49.069` |

Operational reading:

- keep through event `39` / measure `38`
- the current bridge-sized window is the material around events `40-50`
- the return target is event `156` / measure `104`

These are current full-version times, not post-cut times. Once the cut lands, regenerate the timeline immediately.

### Level-Up Plan After The Immediate Cut

The agreed staged restoration path is:

1. start with the immediate rehearsal cut
2. add the rest of page `6`
3. then add page `3`
4. then add pages `4` and `5`

That matters because it argues against destructive cleanup of the middle. Archive and label removed material so it can be reintroduced fast.

### Bridge Development Note

There is also an optional musical idea attached to the bridge:

- grow a synthesized version of approximately measures `100-104`
- let it bloom during the `4` resting measures
- use it to prepare the harmonic return at measure `104`

Treat that as a live development idea, not yet as fixed structure.

## Composer-Facing Control Chain

The current system is effectively this:

`Finale / score export -> MusicXML -> event recipe generation -> event_recipes.json -> conductor + singer apps -> rehearsal/performance`

And in parallel:

`Pro Tools session -> rendered / edited audio -> app or concert playback material`

The most important operational truth is:

- the apps are mostly downstream consumers now
- the real structural source is the score + recipe layer

So if you cut the middle of the piece, the safest order is:

1. reshape the score source
2. regenerate the recipe layer
3. propagate the runtime copies
4. then reshape Pro Tools and audio

## Current Musical Landmarks

Current recipe-driven cue facts:

- `11` trigger events in the current runtime bundle
- trigger labels now include `38.2 / 38.3 / 38.4`
- the cut electronics source keeps original measures `1-41`, then jumps to original measure `104`
- tempo `102 BPM` from measure `1`
- tempo `72 BPM` from measure `30`
- late score text still introduces a freer zone at measures `115` and `130`

### Anchor Points

| Marker | Event / Measure | Time | Why it matters |
| --- | --- | --- | --- |
| opening | Event `1`, measure `1` | `0:00.000` | "Moderato", darkness, water-sound opening |
| early atmosphere | Event `2`, measure `2` | `0:02.353` | first actual cue event after the opening |
| early hush | Event `9`, measure `10` | `0:21.176` | "niente" appears |
| tempo change boundary | measure `30` | `1:08.235` | second encoded tempo begins here |
| cue-timeline quarter point | Event `43`, measure `39` | `1:37.402` | useful orientation marker for first half |
| reverse-impact cluster | Events `72-76`, measure `55` | `2:20.735` to `2:22.819` | explicit labeled sound event in the middle zone |
| cue-timeline midpoint | Event `120`, measure `74` | `3:14.069` | approximate center of the current cue timeline |
| cue-timeline three-quarter point | Event `156`, measure `104` | `4:49.069` | useful for scoping a large interior cut |
| late emphasis | Event `158`, measure `112` | `5:14.069` | "subito" appears |
| aleatoric warning 1 | Event `159`, measure `115` | `5:25.735` | "articulate freely in aleatoric style" |
| aleatoric warning 2 | Event `180`, measure `130` | `6:05.319` | same free-articulation warning returns |
| final cue event | Event `192`, measure `140` | `6:29.902` | "shimmering polytonal sound chandelier" |

### Middle-Of-Piece Orientation

If you are trying to identify the current middle quickly:

- cue midpoint is around `Event 120 / Measure 74 / 3:14`
- the tempo is already in the `72 BPM` zone by then
- the clearly labeled "reversed -impact sound event" cluster is earlier, around `Measure 55 / 2:21`

If the planned cut removes almost half the piece, it will almost certainly remove or heavily restructure a large chunk somewhere around the `Measure 55` to `Measure 104` span, but the actual decision still needs to be made musically by measure/event, not by clock time alone.

For the current working cut, the practical bypass span is now much better defined:

- preserve `1-38`
- use a `4`-measure bridge concept after `38`
- jump to the `104` entrance

So the active structural problem is no longer "where should the cut probably go?" It is "how should the `38 -> bridge -> 104` handoff be realized musically and technically?"

## What Is Actually Wired Into The Apps

The `measure` and `position` values carried by each event should be treated as official trigger points from the annotated trigger-score photos, not as literal sung-note attack times.

### macOS conductor

The conductor event strip is driven by decoded event recipes, not hardcoded event numbers:

- `FlashlightsInTheDark_MacOS/Model/EventRecipe.swift`
- `FlashlightsInTheDark_MacOS/View/EventTriggerStrip.swift`

This is good news. If the event count changes, the UI should mostly follow the new bundle automatically.

### Flutter client

The Flutter client also reads event recipes dynamically:

- `flashlights_client/lib/model/event_recipe.dart`

But the score-practice MusicXML asset path is hardcoded here:

- `flashlights_client/lib/utils/music_xml_utils.dart`

And the asset is explicitly registered here:

- `flashlights_client/pubspec.yaml`

So if you create a renamed cut score file, you must update both of those.

### Stale references to watch

These should be cleaned after the cut lands:

- "nine-minute" / "~9 minutes" text in `README.md`
- the "192 event recipes" comment in `flashlights_client/lib/model/client_state.dart`

They are not the right place to start, but they will become stale immediately after the cut.

## Major Middle Cut: Best Working Method

Do not start by hacking Pro Tools randomly.

The cleanest method is:

1. Pick the cut in score language.
   Write down:
   - start measure
   - end measure
   - nearest start event ID
   - nearest end event ID
2. Decide whether the surviving sections hard-cut, overlap, or need a new bridge.
3. Update the source score.
4. Regenerate the event bundle.
5. Rebuild the timing map.
6. Only then edit Pro Tools to match the new dramatic shape.

This prevents you from solving the same structural problem three times in three different formats.

## Exact Files You Are Likely To Touch For The Cut

### Score and recipe layer

- `Flashlights-ITD_EventRecipes_4_2026_0309/FlashlightsInTheDark_v32_TourCut.musicxml`
- `scripts/generate_event_recipes_v4.py`
- `Flashlights-ITD_EventRecipes_4_2026_0309/event_recipes.json`
- `FlashlightsInTheDark_MacOS/Resources/event_recipes.json`
- `flashlights_client/assets/event_recipes.json`

### Flutter score-practice layer

- `flashlights_client/assets/FlashlightsInTheDark_v32_TourCut.musicxml`
- `flashlights_client/lib/utils/music_xml_utils.dart`
- `flashlights_client/pubspec.yaml`

### Pro Tools / audio layer

- `FlashlightsInTheDark_Protools-Session/2025_0727_FlashlightsInTheDark22_MappingPrimerTones_3.r.ptx`
- `FlashlightsInTheDark_Protools-Session/Audio Files/`
- optionally the generated timeline outputs in `docs/protools-housekeeping/`

### Validation layer

- `docs/protools-housekeeping/event_timeline_events.csv`
- `docs/protools-housekeeping/event_timeline_clips.csv`

Those two CSVs are the fastest way to align the structural control layer with the audio-production layer.

## Practical Next Move For Tonight

The next highest-value step is:

1. confirm the current working cut in `docs/2026-03-13-rehearsal-cut-plan.md`
2. lock the implementation shape of the `38 -> 104` handoff
3. regenerate the control layer before doing broad audio surgery

Concretely:

- preserve the current opening through measure `38`
- decide whether the bridge is adapted from existing measures `39-42`
- or newly composed
- or a hybrid with synthesized `100-104` preparation material
- treat event `156` / measure `104` as the return target
- update the score source first
- then regenerate recipes and timing before going deep in Pro Tools

If you skip that and go straight to Pro Tools, you will almost certainly lose time rebuilding alignment later.

## 24-Hour Composer Triage

If the goal is to get functional quickly, the shortest path is:

1. make the cut shape explicit in the score layer
2. regenerate `event_recipes.json`
3. propagate the updated recipe copies to macOS and Flutter
4. build the bridge and re-entry in Pro Tools
5. run one smoke test across conductor, client, and timing outputs

If time gets tight, protect these first:

- a coherent `38 -> 104` transition
- recipe and app copies staying in sync
- enough preservation of removed middle material to support the later page-by-page restoration plan

## Smoke Test After The Cut

Once the new cut is in place, the minimum useful validation pass is:

1. Regenerate the recipe bundle and timeline outputs.
2. Confirm the event count and ending time look plausible.
3. Confirm the macOS and Flutter recipe JSON copies match.
4. Confirm the Flutter app still loads the correct MusicXML asset.
5. Open the conductor UI and verify event browsing still works.
6. Check one or two representative cue events against Pro Tools timing by ear.

## Anti-Panic Rule

If you start feeling scattered, collapse the task back to this:

`score -> recipe -> runtime copies -> Pro Tools -> smoke test`

That order is the shortest path back to control.
