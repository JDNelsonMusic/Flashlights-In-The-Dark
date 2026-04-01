# Flashlights-In-The-Dark Agent Guide

## Status

This is the active Flashlights repo. Prefer this checkout over the snapshot and recovery clones under `JDN_KEEx-AI_WorkspaceRecords/`.

## What Lives Here

- `FlashlightsInTheDark_MacOS/`: SwiftUI conductor console, OSC routing, MIDI integration, device management, and event triggering.
- `flashlights_client/`: Flutter phone client for iOS and Android.
- `scripts/`: verification, soak testing, onboarding/maintenance, and event/score asset builders.
- `tools/`: concert simulation and support utilities.
- `Flashlights-ITD_EventRecipes_*`: generated cue/timeline assets for current score revisions.
- `docs/project-management/`: concert readiness notes and state maps.

## Start Here

1. Read `README.md`.
2. For live-show or reliability work, read `docs/project-management/CONCERT_READINESS.md`.
3. For cue/timeline changes, inspect the latest `Flashlights-ITD_EventRecipes_*` directory and the corresponding generator scripts in `scripts/`.
4. For phone behavior, work in `flashlights_client/` and keep OSC compatibility with the Mac console.

## Useful Commands

- `scripts/verify.sh`
- `scripts/soak_sim.sh`
- `xcodebuild -project FlashlightsInTheDark.xcodeproj -scheme FlashlightsInTheDark -destination 'platform=macOS' build`
- `cd flashlights_client && flutter pub get`
- `cd flashlights_client && flutter analyze`
- `cd flashlights_client && flutter test`
- `python3 tools/concert_sim.py`

## Guardrails

- Preserve the offline, closed-network performance model and low-latency OSC behavior.
- Treat device-slot maps, trigger positions, and event recipes as concert-critical data.
- Prefer generator scripts over manual edits for derived score/event assets.
- Normal deployment now flows through TestFlight and the Play Store; only use older onboarding scripts when the task explicitly requires maintenance on the legacy path.
- Do not commit real performer identifiers, device identifiers, secrets, or one-off rehearsal artifacts.

