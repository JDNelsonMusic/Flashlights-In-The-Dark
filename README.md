# Flashlights In The Dark

An electro-acoustic work for choir, smartphones, and a Mac-based conductor console. The performance system uses a closed Wi-Fi network and low-latency OSC to synchronize light and sound cues.

## Start by role

| If you are… | Start here |
| --- | --- |
| Engraving or studying the score | [`Engraving/`](Engraving/) |
| Building or regenerating cues | [`Show-Control/`](Show-Control/) and [`Operations/Scripts/`](Operations/Scripts/) |
| Operating the live system | [`Documentation/Project-Management/CONCERT_READINESS.md`](Documentation/Project-Management/CONCERT_READINESS.md) |
| Developing conductor or singer software | [`Software/`](Software/) |
| Working in Pro Tools | [`DAW-Production/`](DAW-Production/) |
| Producing visual material | [`Visual-Production/`](Visual-Production/) |
| Maintaining the public resource hub | [`Web-Surfaces/Communiti-Flashlights/`](Web-Surfaces/Communiti-Flashlights/) |

## Root map

```text
Engraving/          authored MusicXML/PDF scores and score study
Show-Control/       dated event-recipe releases, trigger maps, profiles
Software/           macOS conductor console and Flutter singer client
Web-Surfaces/       public Communiti hub and reusable React package
DAW-Production/     ignored Pro Tools session, committed exports and audits
Visual-Production/  visual references and committed demos
Operations/         scripts, tools, Light Chorus, Fastlane
Documentation/      readiness, technical reference, performance playbooks
```

`docs/demo/` remains temporarily at its legacy path because it contains unresolved local work. It is intentionally excluded from this migration and must not be treated as a new root entry point.

## Concert-critical source flow

1. Author or revise scores in `Engraving/Scores/`.
2. Regenerate dated cues in `Show-Control/Event-Recipes/` with `Operations/Scripts/`.
3. Validate the generated runtime copies in both applications.
4. Run `Operations/Scripts/verify.sh`, `Operations/Scripts/soak_sim.sh`, and the appropriate macOS/Flutter checks before rehearsal.

## Build and validation

```sh
Operations/Scripts/verify.sh
Operations/Scripts/soak_sim.sh
xcodebuild -project Software/Conductor-MacOS/FlashlightsInTheDark.xcodeproj \
  -scheme FlashlightsInTheDark -destination 'platform=macOS' build
(cd Software/Singer-Client && flutter analyze && flutter test)
```

## Public web surface

`Web-Surfaces/Communiti-Flashlights/` is the canonical source for the public, feature-parity Flashlights resource hub and its private reusable component package. Simphoni-Mobile consumes released package versions; it must not carry a divergent local copy.

The Firebase Hosting configuration is checked in, but a production deployment is blocked until an explicit asset-rights review has approved every public score, audio, image, and video asset.

## Guardrails

- Keep the performance network offline and preserve OSC compatibility.
- Do not commit performer identifiers, device identifiers, credentials, or ad-hoc rehearsal material.
- Keep Pro Tools sessions ignored; only approved exports and audit records are tracked.
- Provide audience advisories if using rapid strobe patterns.
