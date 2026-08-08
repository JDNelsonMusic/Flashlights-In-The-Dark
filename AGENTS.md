# Flashlights-In-The-Dark Agent Guide

## Status

This is the active Flashlights repo. Prefer this checkout over snapshot and recovery clones under `JDN_KEEx-AI_WorkspaceRecords/`.

## Root domains

- `Engraving/`: authoritative notation, score study, and score references.
- `Show-Control/`: versioned generated recipes, trigger maps, and runtime profiles.
- `Software/`: the macOS conductor console and Flutter singer client.
- `Web-Surfaces/`: the canonical public Communiti Flashlights web surface and component package.
- `DAW-Production/`: Pro Tools session, tracked exports, and timing/audit outputs.
- `Visual-Production/`: visual references and future committed demos.
- `Operations/`: build, validation, rehearsal, deployment, and support tooling.
- `Documentation/`: concert readiness, technical references, and performance playbooks.

## Start here

1. Read `README.md` and select the relevant domain.
2. For live-show or reliability work, read `Documentation/Project-Management/CONCERT_READINESS.md`.
3. For score/cue work, change the canonical source in `Engraving/` or `Show-Control/`, then regenerate runtime copies through `Operations/Scripts/`.
4. For phone behavior, work in `Software/Singer-Client/` and keep OSC compatibility with `Software/Conductor-MacOS/`.
5. For the public resource hub, work in `Web-Surfaces/Communiti-Flashlights/`; do not duplicate its source in Simphoni-Mobile.

## Useful commands

- `Operations/Scripts/verify.sh`
- `Operations/Scripts/soak_sim.sh`
- `xcodebuild -project Software/Conductor-MacOS/FlashlightsInTheDark.xcodeproj -scheme FlashlightsInTheDark -destination 'platform=macOS' build`
- `cd Software/Singer-Client && flutter analyze && flutter test`
- `python3 Operations/Tools/concert_sim.py`

## Guardrails

- Preserve the offline, closed-network performance model and low-latency OSC behavior.
- Treat device-slot maps, trigger positions, and show-control outputs as concert-critical data.
- Keep authored assets separate from generated/runtime copies; use generators instead of hand-editing derived recipes.
- Do not publish the Web-Surfaces site until its asset-rights review is recorded.
- Do not commit real performer identifiers, device identifiers, secrets, or one-off rehearsal artifacts.
- `docs/demo/` is a temporary dirty-work boundary. Do not move, delete, or normalize it until its owner resolves the current changes.
