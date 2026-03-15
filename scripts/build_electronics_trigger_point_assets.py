#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import json
import shutil
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from build_protools_event_timeline import build_measure_map


ROOT = Path(__file__).resolve().parents[1]
SOURCE_MP3 = (
    ROOT
    / "audio"
    / "protools-exports"
    / "electronics"
    / "2026_0314_FlashlightsInTheDark_Electronics-StereoSum_7.mp3"
)
SCORE_XML = (
    ROOT
    / "Flashlights-ITD_EventRecipes_4_2026_0309"
    / "FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml"
)
TRIGGER_POINT_SOURCE = ROOT / "FlashlightsInTheDark_v31_TwelveTriggerPoints.pdf"
SYNC_REFERENCE_PATH = ROOT / "docs" / "protools-housekeeping" / "electronics_sync_reference.md"
FLUTTER_ASSET_ROOT = (
    ROOT / "flashlights_client" / "available-sounds" / "electronics-trigger-clips"
)
MANIFEST_JSON_PATH = (
    ROOT / "docs" / "protools-housekeeping" / "electronics_trigger_assets.json"
)
MANIFEST_CSV_PATH = (
    ROOT / "docs" / "protools-housekeeping" / "electronics_trigger_assets.csv"
)
RECIPE_COPY_PATHS = [
    ROOT / "Flashlights-ITD_EventRecipes_4_2026_0309" / "event_recipes.json",
    ROOT / "FlashlightsInTheDark_MacOS" / "Resources" / "event_recipes.json",
    ROOT / "flashlights_client" / "assets" / "event_recipes.json",
]
DEFAULT_WORKERS = 4
FADE_IN_MS = 20.0


@dataclass(frozen=True)
class TriggerPointSpec:
    id: int
    measure: int
    beat: int

    @property
    def position_label(self) -> str:
        return f"beat{self.beat}"

    @property
    def score_label(self) -> str:
        return f"M{self.measure}, {self.position_label}"


@dataclass(frozen=True)
class ChoirVariant:
    key: str
    directory: str
    channel_mode: str
    pan_expression: str


TRIGGER_POINTS = (
    TriggerPointSpec(id=1, measure=1, beat=1),
    TriggerPointSpec(id=2, measure=2, beat=1),
    TriggerPointSpec(id=3, measure=25, beat=4),
    TriggerPointSpec(id=4, measure=33, beat=2),
    TriggerPointSpec(id=5, measure=36, beat=1),
    TriggerPointSpec(id=6, measure=46, beat=3),
    TriggerPointSpec(id=7, measure=63, beat=3),
    TriggerPointSpec(id=8, measure=78, beat=1),
    TriggerPointSpec(id=9, measure=89, beat=1),
    TriggerPointSpec(id=10, measure=98, beat=1),
    TriggerPointSpec(id=11, measure=104, beat=1),
    TriggerPointSpec(id=12, measure=115, beat=1),
)

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


def two_beats_ms(tempo_bpm: float) -> float:
    return round(2.0 * 60000.0 / float(tempo_bpm), 3)


def trigger_onset_ms(
    measure_lookup: dict[int, dict[str, Any]],
    trigger: TriggerPointSpec,
) -> tuple[float, float]:
    entry = measure_lookup.get(trigger.measure)
    if entry is None:
        raise ValueError(f"Measure {trigger.measure} missing from score timing map")

    beats = int(entry["beats"])
    if trigger.beat < 1 or trigger.beat > beats:
        raise ValueError(
            f"Trigger point {trigger.id} beat {trigger.beat} outside measure {trigger.measure} ({beats} beats)"
        )

    beat_type = int(entry["beat_type"])
    tempo_bpm = float(entry["tempo_bpm"])
    start_seconds = float(entry["start_seconds"])
    beat_offset_seconds = (trigger.beat - 1) * (4.0 / beat_type) * 60.0 / tempo_bpm
    onset_ms = round((start_seconds + beat_offset_seconds) * 1000.0, 3)
    return onset_ms, tempo_bpm


def variant_asset_key(trigger_id: int, variant: ChoirVariant) -> str:
    return (
        "available-sounds/electronics-trigger-clips/"
        f"{variant.directory}/electronics-trigger-{trigger_id:02d}-{variant.directory}.mp3"
    )


def variant_output_path(trigger_id: int, variant: ChoirVariant) -> Path:
    return ROOT / "flashlights_client" / variant_asset_key(trigger_id, variant)


def render_variant(
    *,
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

    fade_out_ms = min(fade_out_ms, duration_ms)
    fade_out_start_ms = round(duration_ms - fade_out_ms, 3)

    output_path.parent.mkdir(parents=True, exist_ok=True)

    filter_graph = (
        f"atrim=start={start_ms / 1000.0:.6f}:end={end_ms / 1000.0:.6f},"
        "asetpts=PTS-STARTPTS,"
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


def clear_output_root(output_root: Path) -> None:
    if output_root.exists():
        shutil.rmtree(output_root)
    output_root.mkdir(parents=True, exist_ok=True)


def build_trigger_plans(
    *,
    measure_lookup: dict[int, dict[str, Any]],
    source_duration_ms: float,
) -> tuple[list[dict[str, Any]], float]:
    trigger_rows: list[dict[str, Any]] = []
    for trigger in TRIGGER_POINTS:
        onset_ms, tempo_bpm = trigger_onset_ms(measure_lookup, trigger)
        trigger_rows.append(
            {
                "id": trigger.id,
                "measure": trigger.measure,
                "position": trigger.position_label,
                "scoreLabel": trigger.score_label,
                "onsetMs": onset_ms,
                "tempoBpm": tempo_bpm,
            }
        )

    trigger_two = next(row for row in trigger_rows if row["id"] == 2)
    offset_ms = round(11912.0 - float(trigger_two["onsetMs"]), 3)

    plans: list[dict[str, Any]] = []
    for index, trigger in enumerate(trigger_rows):
        file_start_ms = round(float(trigger["onsetMs"]) + offset_ms, 3)
        if index < len(trigger_rows) - 1:
            next_trigger = trigger_rows[index + 1]
            fade_out_ms = two_beats_ms(float(next_trigger["tempoBpm"]))
            file_end_ms = round(float(next_trigger["onsetMs"]) + offset_ms + fade_out_ms, 3)
            timing_rule = "trigger_to_next_trigger_plus_two_beats"
        else:
            fade_out_ms = two_beats_ms(float(trigger["tempoBpm"]))
            file_end_ms = source_duration_ms
            timing_rule = "final_trigger_to_track_end"

        file_end_ms = min(file_end_ms, source_duration_ms)
        duration_ms = round(file_end_ms - file_start_ms, 3)
        if duration_ms <= 0:
            raise ValueError(
                f"Trigger point {trigger['id']} produced invalid duration {duration_ms}"
            )

        variant_payload: dict[str, dict[str, Any]] = {}
        for variant in CHOIR_VARIANTS:
            variant_payload[variant.key] = {
                "sample": variant_asset_key(int(trigger["id"]), variant),
                "channelMode": variant.channel_mode,
                "sourceStartMs": file_start_ms,
                "sourceEndMs": file_end_ms,
                "durationMs": duration_ms,
                "fadeInMs": FADE_IN_MS,
                "fadeOutMs": min(fade_out_ms, duration_ms),
                "timingRule": timing_rule,
            }

        plans.append(
            {
                "id": int(trigger["id"]),
                "measure": int(trigger["measure"]),
                "position": str(trigger["position"]),
                "scoreLabel": str(trigger["scoreLabel"]),
                "onsetMilliseconds": trigger["onsetMs"],
                "tempoBpm": trigger["tempoBpm"],
                "sourceOffsetMs": offset_ms,
                "timingNote": (
                    "Trigger Point 2 anchored to 00:11.912 in the stereo-sum export; "
                    "all other clip boundaries are derived from the score beat map."
                ),
                "variants": variant_payload,
            }
        )

    return plans, offset_ms


def render_assets(
    *,
    source_path: Path,
    plans: list[dict[str, Any]],
) -> None:
    for plan in plans:
        for variant in CHOIR_VARIANTS:
            payload = plan["variants"][variant.key]
            render_variant(
                source_path=source_path,
                output_path=variant_output_path(plan["id"], variant),
                start_ms=float(payload["sourceStartMs"]),
                end_ms=float(payload["sourceEndMs"]),
                fade_in_ms=float(payload["fadeInMs"]),
                fade_out_ms=float(payload["fadeOutMs"]),
                variant=variant,
            )


def build_manifest(
    *,
    generated_at: str,
    source_duration_ms: float,
    offset_ms: float,
    plans: list[dict[str, Any]],
) -> dict[str, Any]:
    return {
        "generated": generated_at,
        "sourceFile": str(SOURCE_MP3.relative_to(ROOT)),
        "sourceDurationMs": source_duration_ms,
        "syncReference": str(SYNC_REFERENCE_PATH.relative_to(ROOT)),
        "triggerPointSource": str(TRIGGER_POINT_SOURCE.relative_to(ROOT)),
        "flutterAssetRoot": str(FLUTTER_ASSET_ROOT.relative_to(ROOT)),
        "triggerPointCount": len(plans),
        "anchorOffsetMs": offset_ms,
        "fadeInMs": FADE_IN_MS,
        "tailRule": "Each clip ends 2 beats after the next trigger point and fades across those final 2 beats.",
        "events": plans,
    }


def write_manifest(manifest: dict[str, Any]) -> None:
    MANIFEST_JSON_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_JSON_PATH.write_text(json.dumps(manifest, indent=2) + "\n")

    with MANIFEST_CSV_PATH.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "id",
                "scoreLabel",
                "measure",
                "position",
                "tempoBpm",
                "variant",
                "channelMode",
                "sourceStartMs",
                "sourceEndMs",
                "durationMs",
                "fadeInMs",
                "fadeOutMs",
                "sample",
            ],
        )
        writer.writeheader()
        for plan in manifest["events"]:
            for variant_key, variant_payload in plan["variants"].items():
                writer.writerow(
                    {
                        "id": plan["id"],
                        "scoreLabel": plan["scoreLabel"],
                        "measure": plan["measure"],
                        "position": plan["position"],
                        "tempoBpm": plan["tempoBpm"],
                        "variant": variant_key,
                        "channelMode": variant_payload["channelMode"],
                        "sourceStartMs": variant_payload["sourceStartMs"],
                        "sourceEndMs": variant_payload["sourceEndMs"],
                        "durationMs": variant_payload["durationMs"],
                        "fadeInMs": variant_payload["fadeInMs"],
                        "fadeOutMs": variant_payload["fadeOutMs"],
                        "sample": variant_payload["sample"],
                    }
                )


def write_recipe_copies(
    *,
    generated_at: str,
    plans: list[dict[str, Any]],
) -> None:
    bundle = {
        "source": str(TRIGGER_POINT_SOURCE.relative_to(ROOT)),
        "triggerPositionSource": str(TRIGGER_POINT_SOURCE.relative_to(ROOT)),
        "triggerTimingNote": (
            "These 12 trigger points come from the annotated twelve-trigger score. "
            "Trigger Point 2 is locked to 00:11.912 in the stereo-sum electronics export. "
            "Each derived clip starts at its own beat-mapped onset and ends 2 beats after the next trigger point."
        ),
        "eventCount": len(plans),
        "generated": generated_at,
        "electronicsSource": str(SOURCE_MP3.relative_to(ROOT)),
        "electronicsSyncReference": str(SYNC_REFERENCE_PATH.relative_to(ROOT)),
        "electronicsManifest": str(MANIFEST_JSON_PATH.relative_to(ROOT)),
        "electronicsGenerated": generated_at,
        "events": [
            {
                "id": plan["id"],
                "measure": plan["measure"],
                "position": plan["position"],
                "scoreLabel": plan["scoreLabel"],
                "timingNote": plan["timingNote"],
                "electronics": plan["variants"],
            }
            for plan in plans
        ],
    }

    payload = json.dumps(bundle, indent=2) + "\n"
    for path in RECIPE_COPY_PATHS:
        path.write_text(payload)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Render the 12 choir-part-specific electronics trigger-point assets "
            "and replace the runtime recipe bundles."
        )
    )
    parser.add_argument(
        "--skip-render",
        action="store_true",
        help="Update manifests and recipe bundles without re-rendering MP3 assets.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if not SOURCE_MP3.exists():
        raise FileNotFoundError(SOURCE_MP3)
    if not SCORE_XML.exists():
        raise FileNotFoundError(SCORE_XML)
    if not TRIGGER_POINT_SOURCE.exists():
        raise FileNotFoundError(TRIGGER_POINT_SOURCE)

    _, measure_lookup = build_measure_map(SCORE_XML)
    source_duration_ms = ffprobe_duration_ms(SOURCE_MP3)
    plans, offset_ms = build_trigger_plans(
        measure_lookup=measure_lookup,
        source_duration_ms=source_duration_ms,
    )
    generated_at = iso_now()

    if not args.skip_render:
        clear_output_root(FLUTTER_ASSET_ROOT)
        render_assets(source_path=SOURCE_MP3, plans=plans)

    manifest = build_manifest(
        generated_at=generated_at,
        source_duration_ms=source_duration_ms,
        offset_ms=offset_ms,
        plans=plans,
    )
    write_manifest(manifest)
    write_recipe_copies(generated_at=generated_at, plans=plans)

    print(f"Rendered {len(plans) * len(CHOIR_VARIANTS)} assets")
    print(f"Manifest: {MANIFEST_JSON_PATH.relative_to(ROOT)}")
    print(f"Recipe copies updated: {len(RECIPE_COPY_PATHS)}")


if __name__ == "__main__":
    main()
