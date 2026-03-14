#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SYNC_REFERENCE_PATH = ROOT / "docs" / "protools-housekeeping" / "electronics_sync_reference.md"
TIMELINE_PATH = ROOT / "docs" / "protools-housekeeping" / "event_timeline.json"
FLUTTER_ASSET_ROOT = ROOT / "flashlights_client" / "available-sounds" / "electronics-event-clips"
MANIFEST_JSON_PATH = ROOT / "docs" / "protools-housekeeping" / "electronics_event_assets.json"
MANIFEST_CSV_PATH = ROOT / "docs" / "protools-housekeeping" / "electronics_event_assets.csv"
RECIPE_COPY_PATHS = [
    ROOT / "Flashlights-ITD_EventRecipes_4_2026_0309" / "event_recipes.json",
    ROOT / "FlashlightsInTheDark_MacOS" / "Resources" / "event_recipes.json",
    ROOT / "flashlights_client" / "assets" / "event_recipes.json",
]
DEFAULT_WORKERS = 4


@dataclass(frozen=True)
class ChoirVariant:
    key: str
    directory: str
    channel_mode: str
    pan_expression: str


CHOIR_VARIANTS = (
    ChoirVariant(
        key="soprano",
        directory="soprano",
        channel_mode="left",
        pan_expression="c0=c0",
    ),
    ChoirVariant(
        key="alto",
        directory="alto",
        channel_mode="right",
        pan_expression="c0=c1",
    ),
    ChoirVariant(
        key="tenor_bass",
        directory="tenor-bass",
        channel_mode="mono_sum",
        pan_expression="c0=0.5*c0+0.5*c1",
    ),
)


def iso_now() -> str:
    return datetime.now(tz=timezone.utc).isoformat(timespec="seconds")


def ffprobe_duration_ms(path: Path) -> float:
    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return round(float(result.stdout.strip()) * 1000.0, 3)


def parse_sync_reference(path: Path) -> tuple[Path, float]:
    text = path.read_text()
    source_match = re.search(r"Source file:\s+`([^`]+)`", text)
    anchor_match = re.search(r"Absolute time in file:\s+`([0-9.]+)`\s+seconds", text)
    if source_match is None or anchor_match is None:
        raise ValueError(f"Unable to parse sync reference: {path}")
    source_path = ROOT / source_match.group(1)
    anchor_ms = round(float(anchor_match.group(1)) * 1000.0, 3)
    return source_path, anchor_ms


def four_beats_ms(tempo_bpm: float) -> float:
    return round(4.0 * 60000.0 / float(tempo_bpm), 3)


def variant_asset_key(event_id: int, variant: ChoirVariant) -> str:
    return (
        f"available-sounds/electronics-event-clips/"
        f"{variant.directory}/electronics-event-{event_id:03d}-{variant.directory}.mp3"
    )


def variant_output_path(event_id: int, variant: ChoirVariant) -> Path:
    return ROOT / "flashlights_client" / variant_asset_key(event_id, variant)


def render_variant(
    source_path: Path,
    output_path: Path,
    start_ms: float,
    end_ms: float,
    fade_in_ms: float,
    fade_out_ms: float,
    variant: ChoirVariant,
) -> None:
    duration_ms = round(end_ms - start_ms, 3)
    if duration_ms <= 0:
        raise ValueError(f"Non-positive clip duration for {output_path.name}: {duration_ms}")

    fade_out_start_ms = round(duration_ms - fade_out_ms, 3)
    if fade_out_start_ms < 0:
        raise ValueError(f"Fade-out longer than clip duration for {output_path.name}")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    filter_graph = (
        f"atrim=start={start_ms / 1000.0:.6f}:end={end_ms / 1000.0:.6f},"
        f"asetpts=PTS-STARTPTS,"
        f"pan=mono|{variant.pan_expression},"
        f"afade=t=in:st=0:d={fade_in_ms / 1000.0:.6f},"
        f"afade=t=out:st={fade_out_start_ms / 1000.0:.6f}:d={fade_out_ms / 1000.0:.6f}"
    )

    subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-y",
            "-i",
            str(source_path),
            "-filter:a",
            filter_graph,
            "-codec:a",
            "libmp3lame",
            "-q:a",
            "2",
            str(output_path),
        ],
        check=True,
    )


def build_event_plan(
    timeline_events: list[dict[str, Any]],
    source_duration_ms: float,
    anchor_file_ms: float,
) -> list[dict[str, Any]]:
    if len(timeline_events) != 192:
        raise ValueError(f"Expected 192 events, found {len(timeline_events)}")

    event2 = next((event for event in timeline_events if event["id"] == 2), None)
    if event2 is None:
        raise ValueError("Event 2 missing from event timeline")

    offset_ms = round(anchor_file_ms - float(event2["onset_milliseconds"]), 3)
    fade_in_ms = 20.0
    plans: list[dict[str, Any]] = []

    for index, event in enumerate(timeline_events):
        event_id = int(event["id"])
        start_ms: float
        end_ms: float
        fade_out_ms: float
        timing_rule: str

        if event_id == 1:
            start_ms = 0.0
            end_ms = 14000.0
            fade_out_ms = four_beats_ms(float(event["tempo_bpm"]))
            timing_rule = "event_1_fixed_window"
        elif event_id == 192:
            start_ms = round(float(event["onset_milliseconds"]) + offset_ms, 3)
            end_ms = source_duration_ms
            fade_out_ms = four_beats_ms(float(event["tempo_bpm"]))
            timing_rule = "event_192_to_track_end"
        else:
            next_event = timeline_events[index + 1]
            start_ms = round(float(event["onset_milliseconds"]) + offset_ms, 3)
            fade_out_ms = four_beats_ms(float(next_event["tempo_bpm"]))
            end_ms = round(float(next_event["onset_milliseconds"]) + offset_ms + fade_out_ms, 3)
            timing_rule = "event_to_next_event_plus_four_beats"

        if end_ms > source_duration_ms:
            end_ms = source_duration_ms

        duration_ms = round(end_ms - start_ms, 3)
        if duration_ms <= 0:
            raise ValueError(f"Invalid duration for event {event_id}: {duration_ms}")

        variant_payload = {}
        for variant in CHOIR_VARIANTS:
            asset_key = variant_asset_key(event_id, variant)
            variant_payload[variant.key] = {
                "sample": asset_key,
                "channelMode": variant.channel_mode,
                "sourceStartMs": start_ms,
                "sourceEndMs": end_ms,
                "durationMs": duration_ms,
                "fadeInMs": fade_in_ms,
                "fadeOutMs": fade_out_ms,
                "timingRule": timing_rule,
            }

        plans.append(
            {
                "id": event_id,
                "measure": int(event["measure"]),
                "position": event["position"],
                "onsetMilliseconds": int(event["onset_milliseconds"]),
                "tempoBpm": float(event["tempo_bpm"]),
                "timingNote": event.get("timing_note"),
                "sourceOffsetMs": offset_ms,
                "variants": variant_payload,
            }
        )

    return plans


def render_assets(source_path: Path, plans: list[dict[str, Any]], workers: int) -> None:
    futures = []
    with ThreadPoolExecutor(max_workers=workers) as executor:
        for plan in plans:
            for variant in CHOIR_VARIANTS:
                payload = plan["variants"][variant.key]
                futures.append(
                    executor.submit(
                        render_variant,
                        source_path=source_path,
                        output_path=variant_output_path(plan["id"], variant),
                        start_ms=float(payload["sourceStartMs"]),
                        end_ms=float(payload["sourceEndMs"]),
                        fade_in_ms=float(payload["fadeInMs"]),
                        fade_out_ms=float(payload["fadeOutMs"]),
                        variant=variant,
                    )
                )

        for future in as_completed(futures):
            future.result()


def write_manifest(
    source_path: Path,
    source_duration_ms: float,
    plans: list[dict[str, Any]],
    generated_at: str,
) -> None:
    payload = {
        "generated": generated_at,
        "sourceFile": str(source_path.relative_to(ROOT)),
        "sourceDurationMs": source_duration_ms,
        "flutterAssetRoot": str(FLUTTER_ASSET_ROOT.relative_to(ROOT)),
        "eventCount": len(plans),
        "renderedAssetCount": len(plans) * len(CHOIR_VARIANTS),
        "events": plans,
    }
    MANIFEST_JSON_PATH.write_text(json.dumps(payload, indent=2) + "\n")

    rows = []
    for plan in plans:
        for variant in CHOIR_VARIANTS:
            variant_payload = plan["variants"][variant.key]
            rows.append(
                {
                    "event_id": plan["id"],
                    "measure": plan["measure"],
                    "position": plan["position"],
                    "variant": variant.key,
                    "channel_mode": variant_payload["channelMode"],
                    "sample": variant_payload["sample"],
                    "source_start_ms": variant_payload["sourceStartMs"],
                    "source_end_ms": variant_payload["sourceEndMs"],
                    "duration_ms": variant_payload["durationMs"],
                    "fade_in_ms": variant_payload["fadeInMs"],
                    "fade_out_ms": variant_payload["fadeOutMs"],
                    "timing_rule": variant_payload["timingRule"],
                    "timing_note": plan["timingNote"] or "",
                }
            )

    with MANIFEST_CSV_PATH.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def patch_recipe_copy(path: Path, plans_by_id: dict[int, dict[str, Any]], generated_at: str) -> None:
    bundle = json.loads(path.read_text())
    bundle["electronicsSource"] = "audio/protools-exports/electronics/2026_0314_FlashlightsInTheDark_Electronics-StereoSum_7.mp3"
    bundle["electronicsSyncReference"] = "docs/protools-housekeeping/electronics_sync_reference.md"
    bundle["electronicsManifest"] = "docs/protools-housekeeping/electronics_event_assets.json"
    bundle["electronicsGenerated"] = generated_at

    for event in bundle.get("events", []):
        event_id = int(event["id"])
        plan = plans_by_id[event_id]
        event["electronics"] = plan["variants"]

    path.write_text(json.dumps(bundle, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Render choir-part-specific electronics event assets and patch event recipe copies."
    )
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    args = parser.parse_args()

    source_path, anchor_file_ms = parse_sync_reference(SYNC_REFERENCE_PATH)
    timeline = json.loads(TIMELINE_PATH.read_text())
    timeline_events = timeline["events"]
    source_duration_ms = ffprobe_duration_ms(source_path)
    generated_at = iso_now()
    plans = build_event_plan(
        timeline_events=timeline_events,
        source_duration_ms=source_duration_ms,
        anchor_file_ms=anchor_file_ms,
    )
    render_assets(source_path=source_path, plans=plans, workers=max(1, args.workers))
    write_manifest(
        source_path=source_path,
        source_duration_ms=source_duration_ms,
        plans=plans,
        generated_at=generated_at,
    )

    plans_by_id = {plan["id"]: plan for plan in plans}
    for recipe_path in RECIPE_COPY_PATHS:
        patch_recipe_copy(recipe_path, plans_by_id, generated_at)

    print(f"Rendered {len(plans) * len(CHOIR_VARIANTS)} assets")
    print(f"Wrote {MANIFEST_JSON_PATH.relative_to(ROOT)}")
    for recipe_path in RECIPE_COPY_PATHS:
        print(f"Patched {recipe_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
