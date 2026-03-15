#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

PROFILE_MANIFEST = {
    "activeProfileId": "tour_cut",
    "profiles": [
        {
            "id": "tour_cut",
            "label": "Tour Cut",
            "shortLabel": "Tour",
            "runtimeReady": True,
            "triggerCount": 8,
            "scoreMusicXml": "Flashlights-ITD_EventRecipes_4_2026_0309/FlashlightsInTheDark_v32_TourCut.musicxml",
            "triggerPositionSource": "docs/score-study/tour_cut_trigger_points.csv",
            "electronicsManifest": "docs/protools-housekeeping/electronics_trigger_assets.json",
            "lightShowManifest": "docs/score-study/tour_cut_light_show.json",
            "notes": "Current performance runtime bundle with tour-cut score, 8 trigger points, and TP8 part-specific musique concrete.",
        },
        {
            "id": "full_version",
            "label": "Full Version",
            "shortLabel": "Full",
            "runtimeReady": False,
            "triggerCount": 12,
            "scoreMusicXml": "Flashlights-ITD_EventRecipes_4_2026_0309/FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml",
            "triggerPositionSource": "docs/score-study/full_version_trigger_points.csv",
            "electronicsManifest": "docs/protools-housekeeping/electronics_trigger_assets.json",
            "lightShowManifest": "docs/score-study/twelve_trigger_light_show.json",
            "notes": "Profile is registered and documented, but the shipped runtime currently remains tour-cut only until a dedicated full-version bundle is regenerated.",
        },
    ],
}

PROFILE_COPY_PATHS = [
    ROOT / "docs" / "show-profiles" / "show_profiles.json",
    ROOT / "FlashlightsInTheDark_MacOS" / "Resources" / "show_profiles.json",
    ROOT / "flashlights_client" / "assets" / "show_profiles.json",
]

ACTIVE_RECIPE_PATHS = [
    ROOT / "Flashlights-ITD_EventRecipes_4_2026_0309" / "event_recipes.json",
    ROOT / "FlashlightsInTheDark_MacOS" / "Resources" / "event_recipes.json",
    ROOT / "flashlights_client" / "assets" / "event_recipes.json",
]

ACTIVE_PROFILE_METADATA = {
    "tour_cut": {
        "profileId": "tour_cut",
        "profileLabel": "Tour Cut",
        "lightShowManifest": "docs/score-study/tour_cut_light_show.json",
    },
    "full_version": {
        "profileId": "full_version",
        "profileLabel": "Full Version",
        "lightShowManifest": "docs/score-study/twelve_trigger_light_show.json",
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
    for path in ACTIVE_RECIPE_PATHS:
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload.update(metadata)
        write_json(path, payload)


def run_script(script_name: str) -> None:
    script_path = ROOT / "scripts" / script_name
    subprocess.run(["python3", str(script_path)], cwd=ROOT, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Regenerate the active show runtime bundle and sync profile manifests."
    )
    parser.add_argument(
        "--active-profile",
        default="tour_cut",
        choices=["tour_cut", "full_version"],
        help="Profile to mark as active in the generated manifests.",
    )
    parser.add_argument(
        "--profiles-only",
        action="store_true",
        help="Only write show profile metadata and recipe annotations.",
    )
    args = parser.parse_args()

    if args.active_profile != "tour_cut" and not args.profiles_only:
        raise SystemExit(
            "The full-version runtime bundle is not yet regenerated in this pipeline. "
            "Use --active-profile tour_cut or run with --profiles-only."
        )

    sync_profile_manifest(args.active_profile)

    if not args.profiles_only:
        run_script("build_tour_cut_score.py")
        run_script("build_electronics_trigger_point_assets.py")
        run_script("build_trigger_point_light_show.py")
        run_script("build_protools_event_timeline.py")

    annotate_active_recipe_bundles(args.active_profile)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
