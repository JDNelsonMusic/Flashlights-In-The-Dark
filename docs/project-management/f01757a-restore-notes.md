# f01757a Snapshot Restore Notes

Last updated: May 19, 2026

This PR restores the review-safe parts of the July 8, 2025 `f01757a` snapshot onto current `main`.

## Source

- Requested source branch: `restore-f01757a`
- Available source in this checkout: commit `f01757acdb8063c39a571f8b05d99254e4936af3`
- Merge base with current `origin/main`: `dcc8f8602b2cfdb49d05a10687a87afca1e8ebf9`

The branch name was not present in local or remote refs, so the commit object was used as the snapshot source. Histories are related; no unrelated-history merge was needed.

## Restored

- `FlashlightsInTheDark_Icons/` from `f01757a`, preserving the original exported source app icons.
- Deprecated onboarding/icon-generation path references were updated so they no longer point at `~/AI_Dev` or a user-specific absolute path.

## Intentionally Excluded

- Xcode `xcuserdata` and `*.xcuserstate` files from the snapshot, because they are per-user workspace state.
- `FlashlightsInTheDark_Protools-Session/*.ptx`, backup session files, and `*.wfm` cache files, because current `.gitignore` intentionally excludes Pro Tools sessions and waveform caches. If those session binaries need to live in GitHub, add Git LFS tracking first and restore them in a dedicated PR.
- Deleted backup-session churn from `f01757a`; current `main` remains the source of truth for the modern concert code, docs, recipes, and deployment assets.

## Apex-01 / Simphoni Compatibility

Flashlights remains an offline, closed-network performance system. The supported runtime is a Mac conductor plus Flutter phone clients on the same performance Wi-Fi, communicating over OSC. No Apex-01, OpenAI, Ollama, local LLM, or Simphoni cloud endpoint is required for the restored runtime path.

Repo search still shows adjacent experimental Simphoni material under `src/` and `SimphoniMacOS/SimphoniBackgroundService_Pack/`. Those files are not part of the restored Flashlights performance runtime, and this PR does not invent Apex-01 or Simphoni service endpoints for them.

When using legacy onboarding scripts, keep local paths configurable:

- `FLASHLIGHTS_IPA_PATH`: optional path to a prebuilt iOS IPA for USB install workflows.
- `FLASHLIGHTS_ARCHIVE_PATH`: optional path to a local Xcode archive for re-export workflows.
- `FLASHLIGHTS_MAP_PATH`: optional path to the device map JSON; defaults to `FlashlightsInTheDark_MacOS/flash_ip+udid_map.json`.

Normal deployment remains TestFlight for iOS and Play Store for Android.
