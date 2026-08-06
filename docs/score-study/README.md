# Score Study Archive

This folder contains collected score-study submissions and supporting archive material.

- `FlashlightsScoreStudyInsights/`: extracted reference images by contributor
- `FlashlightsScoreStudyInsights.zip`: archived bundle of the same material

## Full-version light-show prototype

`Flashlights_Lightshow_Prototype_Schema.json` keeps the twelve operator trigger
points from the v26 full score while defining eighteen internal visual sections.
The sections are derived from MusicXML measure timing and cover M1 through M151
without gaps. Each trigger event contains `visualSectionWindows` with local
millisecond offsets, so a single operator cue can carry multiple visual scenes.

Regenerate the section model with:

```bash
python3 scripts/build_full_version_section_model.py
```

This builder intentionally does not modify the active Tour Cut runtime bundle.
