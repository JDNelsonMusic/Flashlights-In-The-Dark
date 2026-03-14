# Official Trigger Positions

The authoritative `192` event trigger positions for this project are the notated trigger points shown in:

- `docs/reference-images/official-trigger-score/Flashlights_OfficialEventPositions_pg1.jpeg`
- `docs/reference-images/official-trigger-score/Flashlights_OfficialEventPositions_pg2.jpeg`

Those images define the official measure/beat location for every event used by the conductor, the mobile client, the event-recipe spreadsheet, and downstream timing work.

## Timing Semantics

- The event `measure` and `position` fields throughout the repo are trigger points, not sung-note onsets.
- In rehearsal testing, the triggering system has behaved as though there is roughly a half-note of latency.
- The short primer tones are intentionally designed to sound an eighth-note before the note that singers are meant to sing.
- As a result, most trigger points are intentionally notated about one beat before the sung event they are teeing up, with a few deliberate compositional exceptions.

## Machine-Readable Source

- Canonical file: `Flashlights-ITD_EventRecipes_4_2026_0309/official_trigger_positions.csv`
- Derived copies:
  - `Flashlights-ITD_EventRecipes_4_2026_0309/event_recipes.json`
  - `FlashlightsInTheDark_MacOS/Resources/event_recipes.json`
  - `flashlights_client/assets/event_recipes.json`
  - `Flashlights-ITD_EventRecipes_4_2026_0309/Flashlights-ITD_EventRecipes_4.csv`
  - `Flashlights-ITD_EventRecipes_4_2026_0309/Flashlights-ITD_EventRecipes_4.xlsx`

If an event's trigger point ever changes, update `official_trigger_positions.csv` first and regenerate the downstream recipe outputs.
