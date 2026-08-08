#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

PROFILE_MANIFEST = {
    "activeProfileId": "full_version",
    "profiles": [
        {
            "id": "tour_cut",
            "label": "Tour Cut",
            "shortLabel": "Tour",
            "runtimeReady": False,
            "triggerCount": 7,
            "scoreMusicXml": "Engraving/Scores/FlashlightsInTheDark_v32_TourCut.musicxml",
            "triggerPositionSource": "Engraving/Score-Study/tour_cut_trigger_points.csv",
            "electronicsManifest": "DAW-Production/Audits/electronics_trigger_assets.json",
            "lightShowManifest": "Engraving/Score-Study/tour_cut_light_show.json",
            "notes": "Archived tour-cut runtime profile retained for reference; not the planned December 2026 performance state.",
        },
        {
            "id": "full_version",
            "label": "Full Version",
            "shortLabel": "Full",
            "runtimeReady": True,
            "triggerCount": 12,
            "scoreMusicXml": "Engraving/Scores/FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml",
            "triggerPositionSource": "Engraving/Score-Study/full_version_trigger_points.csv",
            "electronicsManifest": "DAW-Production/Audits/electronics_trigger_assets.json",
            "lightShowManifest": "Engraving/Score-Study/twelve_trigger_light_show.json",
            "notes": "Planned December 2026 runtime profile with twelve macro trigger points and restored middle-section light choreography.",
        },
    ],
}

PROFILE_COPY_PATHS = [
    ROOT / "Show-Control" / "Show-Profiles" / "show_profiles.json",
    ROOT / "Software/Conductor-MacOS/FlashlightsInTheDark_MacOS" / "Resources" / "show_profiles.json",
    ROOT / "Software/Singer-Client" / "assets" / "show_profiles.json",
]

ACTIVE_RECIPE_PATHS = [
    ROOT / "Show-Control/Event-Recipes/Flashlights-ITD_EventRecipes_4_2026_0309" / "event_recipes.json",
    ROOT / "Software/Conductor-MacOS/FlashlightsInTheDark_MacOS" / "Resources" / "event_recipes.json",
    ROOT / "Software/Singer-Client" / "assets" / "event_recipes.json",
]

ACTIVE_PROFILE_METADATA = {
    "tour_cut": {
        "profileId": "tour_cut",
        "profileLabel": "Tour Cut",
        "lightShowManifest": "Engraving/Score-Study/tour_cut_light_show.json",
    },
    "full_version": {
        "profileId": "full_version",
        "profileLabel": "Full Version",
        "lightShowManifest": "Engraving/Score-Study/twelve_trigger_light_show.json",
    },
}


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def sync_profile_manifest(active_profile: str) -> None:
    manifest = dict(PROFILE_MANIFEST)
    manifest["activeProfileId"] = active_profile
    for path in PROFILE_COPY_PATHS:
        write_json(path, manifest)


def annotate_active_recipe_bundles(active_profile: str) -> None:
    metadata = ACTIVE_PROFILE_METADATA[active_profile]
    canonical_payload = None
    for path in ACTIVE_RECIPE_PATHS:
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload.update(metadata)
        if canonical_payload is None:
            canonical_payload = payload

    if canonical_payload is None:
        return

    for path in ACTIVE_RECIPE_PATHS:
        write_json(path, canonical_payload)


def run_script(script_name: str, *args: str) -> None:
    script_path = ROOT / "Operations" / "Scripts" / script_name
    subprocess.run(["python3", str(script_path), *args], cwd=ROOT, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Regenerate the active show runtime bundle and sync profile manifests."
    )
    parser.add_argument(
        "--active-profile",
        default="full_version",
        choices=["tour_cut", "full_version"],
        help="Profile to mark as active in the generated manifests.",
    )
    parser.add_argument(
        "--profiles-only",
        action="store_true",
        help="Only write show profile metadata and recipe annotations.",
    )
    args = parser.parse_args()

    sync_profile_manifest(args.active_profile)

    if not args.profiles_only:
        if args.active_profile == "tour_cut":
            run_script("build_tour_cut_score.py")
        run_script(
            "build_electronics_trigger_point_assets.py",
            "--active-profile",
            args.active_profile,
        )
        run_script(
            "build_trigger_point_light_show.py",
            "--active-profile",
            args.active_profile,
        )
        profile = next(
            item for item in PROFILE_MANIFEST["profiles"] if item["id"] == args.active_profile
        )
        run_script(
            "build_protools_event_timeline.py",
            "--score-xml",
            profile["scoreMusicXml"],
        )

    annotate_active_recipe_bundles(args.active_profile)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
