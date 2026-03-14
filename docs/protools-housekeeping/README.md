# Pro Tools Housekeeping

This folder contains the first-pass housekeeping outputs for the Pro Tools materials in `FlashlightsInTheDark_Protools-Session`.

## Canonical Sources

- Working session candidate: `FlashlightsInTheDark_Protools-Session/2025_0727_FlashlightsInTheDark22_MappingPrimerTones_3.r.ptx`
- Cue bundle: `Flashlights-ITD_EventRecipes_4_2026_0309/event_recipes.json`
- Score timing source: `Flashlights-ITD_EventRecipes_4_2026_0309/FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml`
- Runtime recipe copies: identical across the recipe bundle, macOS resources, and Flutter assets
- Runtime primer assets: identical across macOS and Flutter, with `98` matched MP3 files and no hash mismatches

These are recommendations, not destructive edits. Confirm the session choice in Pro Tools before deleting, renaming, or archiving anything.

## Generated Outputs

- `session_audit.md` and `session_audit.json`: session inventory, backup lineage, suspicious filenames, and cleanup candidates
- `event_timeline.md`: score-time timing summary and integration checks
- `event_timeline.json`: event-level and clip-level timeline data with performance-time onsets
- `event_timeline_events.csv`: one row per event
- `event_timeline_clips.csv`: one row per color/sample assignment

## Immediate Safe Actions

- Remove `.DS_Store` files from the Pro Tools session tree.
- Ignore or remove empty directories: `Bounced Files`, `Clip Groups`, `Rendered Files`, `untitled folder`.
- Treat `ExtractingSop1.r.ptx` and `jgfchgfchgfcxh.r.ptx` as manual-review scratch sessions until the working session is confirmed.

## Next Cleanup Pass

1. Open `2025_0727_FlashlightsInTheDark22_MappingPrimerTones_3.r.ptx` in Pro Tools and confirm it is the intended live session.
2. Decide whether the long-name and `simphoni_*` families are source ideas, scratch renders, or material that still belongs in the active session.
3. After that decision, build a rename map for the irregular files rather than renaming ad hoc.
4. Use `event_timeline_clips.csv` as the timing grid for any clip duplication, fades, splices, or rendered replacements.
5. If you export MIDI, marker lists, or clip lists from Pro Tools later, add them here and reconcile them against the generated timeline.

## Regeneration

Run these from the repository root:

```bash
python3 scripts/audit_protools_session.py
python3 scripts/build_protools_event_timeline.py
```
