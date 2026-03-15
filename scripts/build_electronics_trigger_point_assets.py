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

from score_measure_utils import build_measure_token_map


ROOT = Path(__file__).resolve().parents[1]
FULL_SOURCE_MP3 = (
    ROOT
    / "audio"
    / "protools-exports"
    / "electronics"
    / "2026_0314_FlashlightsInTheDark_Electronics-StereoSum_7.mp3"
)
CUT_SOURCE_MP3 = (
    ROOT
    / "audio"
    / "protools-exports"
    / "electronics"
    / "2026_0314_FlashlightsInTheDark_Electronics-StereoSum_7_TourCut.mp3"
)
MUSIQUE_CONCRETE_SOURCE_ROOT = (
    ROOT / "audio" / "protools-exports" / "musique-concrete"
)
FULL_SCORE_XML = (
    ROOT
    / "Flashlights-ITD_EventRecipes_4_2026_0309"
    / "FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml"
)
CUT_SCORE_XML = (
    ROOT
    / "Flashlights-ITD_EventRecipes_4_2026_0309"
    / "FlashlightsInTheDark_v32_TourCut.musicxml"
)
TRIGGER_POINT_SOURCE = ROOT / "docs" / "score-study" / "tour_cut_trigger_points.csv"
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
FADE_IN_MS = 20.0
FIRST_TRIGGER_START_MS = 2000.0
CROSSFADE_BEATS = 1.0
TP8_CONCRETE_FADE_IN_BEATS = 2.0
TP8_CONCRETE_FADE_OUT_BEATS = 1.0


@dataclass(frozen=True)
class TriggerPointSpec:
    id: int
    measure_token: str
    measure: int
    position_label: str
    score_label: str
    role: str
    source_measure_token: str
    source_measure: int

    @property
    def beat(self) -> int:
        raw = self.position_label.strip().lower()
        if not raw.startswith("beat"):
            raise ValueError(f"Unsupported position label: {self.position_label}")
        return int(raw[4:])


@dataclass(frozen=True)
class ChoirVariant:
    key: str
    directory: str
    channel_mode: str
    pan_expression: str


@dataclass(frozen=True)
class PartConcreteVariant:
    part_key: str
    directory: str
    source_name: str
    label: str


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

PART_CONCRETE_VARIANTS = (
    PartConcreteVariant(
        part_key="soprano_l1",
        directory="soprano-l1",
        source_name="MusiqueConcrete_Track1.mp3",
        label="Sop-L1",
    ),
    PartConcreteVariant(
        part_key="soprano_l2",
        directory="soprano-l2",
        source_name="MusiqueConcrete_Track1_2.mp3",
        label="Sop-L2",
    ),
    PartConcreteVariant(
        part_key="tenor_l",
        directory="tenor-l",
        source_name="MusiqueConcrete_Track1_3.mp3",
        label="Ten-L",
    ),
    PartConcreteVariant(
        part_key="bass_l",
        directory="bass-l",
        source_name="MusiqueConcrete_Track1_4.mp3",
        label="Bass-L",
    ),
    PartConcreteVariant(
        part_key="alto_l2",
        directory="alto-l2",
        source_name="MusiqueConcrete_Track1_5.mp3",
        label="Alto-L2",
    ),
    PartConcreteVariant(
        part_key="alto_l1",
        directory="alto-l1",
        source_name="MusiqueConcrete_Track1_6.mp3",
        label="Alto-L1",
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


def beat_ms(tempo_bpm: float, beat_count: float = 1.0) -> float:
    return round(float(beat_count) * 60000.0 / float(tempo_bpm), 3)


def load_trigger_specs(path: Path) -> list[TriggerPointSpec]:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))

    specs = [
        TriggerPointSpec(
            id=int(row["id"]),
            measure_token=row["measure_token"].strip(),
            measure=int(row["measure"]),
            position_label=row["position"].strip(),
            score_label=row["score_label"].strip(),
            role=row.get("role", "").strip(),
            source_measure_token=row.get("source_measure_token", row["measure_token"]).strip(),
            source_measure=int(row.get("source_measure", row["measure"])),
        )
        for row in rows
    ]
    ids = [spec.id for spec in specs]
    if len(set(ids)) != len(ids):
        raise ValueError("Trigger IDs must be unique")
    return specs


def trigger_onset_ms(
    token_lookup: dict[str, dict[str, Any]],
    trigger: TriggerPointSpec,
) -> tuple[float, float, int]:
    entry = token_lookup.get(trigger.measure_token)
    if entry is None:
        raise ValueError(f"Measure token {trigger.measure_token} missing from score timing map")

    beats = int(entry["beats"])
    if trigger.beat < 1 or trigger.beat > beats:
        raise ValueError(
            f"Trigger point {trigger.id} beat {trigger.beat} outside measure {trigger.measure_token} ({beats} beats)"
        )

    beat_type = int(entry["beat_type"])
    tempo_bpm = float(entry["tempo_bpm"])
    start_seconds = float(entry["start_seconds"])
    beat_offset_seconds = (trigger.beat - 1) * (4.0 / beat_type) * 60.0 / tempo_bpm
    onset_ms = round((start_seconds + beat_offset_seconds) * 1000.0, 3)
    return onset_ms, tempo_bpm, int(entry["ordinal"])


def variant_asset_key(trigger_id: int, variant: ChoirVariant) -> str:
    return (
        "available-sounds/electronics-trigger-clips/"
        f"{variant.directory}/electronics-trigger-{trigger_id:02d}-{variant.directory}.mp3"
    )


def variant_output_path(trigger_id: int, variant: ChoirVariant) -> Path:
    return ROOT / "flashlights_client" / variant_asset_key(trigger_id, variant)


def part_concrete_asset_key(trigger_id: int, variant: PartConcreteVariant) -> str:
    return (
        "available-sounds/electronics-trigger-clips/part-specific/"
        f"{variant.directory}/electronics-trigger-{trigger_id:02d}-{variant.directory}-musique-concrete.mp3"
    )


def part_concrete_output_path(trigger_id: int, variant: PartConcreteVariant) -> Path:
    return ROOT / "flashlights_client" / part_concrete_asset_key(trigger_id, variant)


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


def render_passthrough_variant(
    *,
    source_path: Path,
    output_path: Path,
    start_ms: float,
    end_ms: float,
    fade_in_ms: float,
    fade_out_ms: float,
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


def render_cut_source(
    *,
    full_source_path: Path,
    output_path: Path,
    full_token_lookup: dict[str, dict[str, Any]],
    cut_token_lookup: dict[str, dict[str, Any]],
    trigger_specs: list[TriggerPointSpec],
) -> None:
    trigger_by_id = {trigger.id: trigger for trigger in trigger_specs}
    trigger5 = trigger_by_id[5]
    trigger8 = trigger_by_id[8]
    trigger11 = trigger_by_id[11]

    full_5_ms, _, _ = trigger_onset_ms(
        full_token_lookup,
        TriggerPointSpec(
            id=trigger5.id,
            measure_token=trigger5.source_measure_token,
            measure=trigger5.source_measure,
            position_label=trigger5.position_label,
            score_label=trigger5.score_label,
            role=trigger5.role,
            source_measure_token=trigger5.source_measure_token,
            source_measure=trigger5.source_measure,
        ),
    )
    full_8_ms, _, _ = trigger_onset_ms(
        full_token_lookup,
        TriggerPointSpec(
            id=trigger8.id,
            measure_token=trigger8.source_measure_token,
            measure=trigger8.source_measure,
            position_label=trigger8.position_label,
            score_label=trigger8.score_label,
            role=trigger8.role,
            source_measure_token=trigger8.source_measure_token,
            source_measure=trigger8.source_measure,
        ),
    )
    full_11_ms, _, _ = trigger_onset_ms(
        full_token_lookup,
        TriggerPointSpec(
            id=trigger11.id,
            measure_token=trigger11.source_measure_token,
            measure=trigger11.source_measure,
            position_label=trigger11.position_label,
            score_label=trigger11.score_label,
            role=trigger11.role,
            source_measure_token=trigger11.source_measure_token,
            source_measure=trigger11.source_measure,
        ),
    )

    cut_5_ms, _, _ = trigger_onset_ms(cut_token_lookup, trigger5)
    cut_8_ms, tempo_8_bpm, _ = trigger_onset_ms(cut_token_lookup, trigger8)
    cut_11_ms, _, _ = trigger_onset_ms(cut_token_lookup, trigger11)

    span_5_to_8_ms = round(cut_8_ms - cut_5_ms, 3)
    span_8_to_11_ms = round(cut_11_ms - cut_8_ms, 3)
    if span_5_to_8_ms <= 0 or span_8_to_11_ms <= 0:
        raise ValueError("Tour-cut trigger ordering is invalid for 5 -> 8 -> 11")

    crossfade_ms = round((60000.0 / tempo_8_bpm) * CROSSFADE_BEATS, 3)
    segment_5_ms = span_5_to_8_ms + crossfade_ms
    segment_8_ms = span_8_to_11_ms

    output_path.parent.mkdir(parents=True, exist_ok=True)
    filter_graph = (
        f"[0:a]atrim=start=0:end={full_5_ms / 1000.0:.6f},asetpts=PTS-STARTPTS[pre];"
        f"[0:a]atrim=start={full_5_ms / 1000.0:.6f}:end={(full_5_ms + segment_5_ms) / 1000.0:.6f},asetpts=PTS-STARTPTS[seg5];"
        f"[0:a]atrim=start={full_8_ms / 1000.0:.6f}:end={(full_8_ms + segment_8_ms) / 1000.0:.6f},asetpts=PTS-STARTPTS[seg8];"
        f"[seg5][seg8]acrossfade=d={crossfade_ms / 1000.0:.6f}[bridge];"
        f"[0:a]atrim=start={full_11_ms / 1000.0:.6f},asetpts=PTS-STARTPTS[tail];"
        "[pre][bridge][tail]concat=n=3:v=0:a=1[out]"
    )
    subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-y",
            "-i",
            str(full_source_path),
            "-filter_complex",
            filter_graph,
            "-map",
            "[out]",
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
    token_lookup: dict[str, dict[str, Any]],
    source_duration_ms: float,
    trigger_specs: list[TriggerPointSpec],
) -> tuple[list[dict[str, Any]], float]:
    trigger_rows: list[dict[str, Any]] = []
    for trigger in trigger_specs:
        onset_ms, tempo_bpm, ordinal = trigger_onset_ms(token_lookup, trigger)
        trigger_rows.append(
            {
                "id": trigger.id,
                "measure": trigger.measure,
                "measureToken": trigger.measure_token,
                "scoreMeasureOrdinal": ordinal,
                "position": trigger.position_label,
                "scoreLabel": trigger.score_label,
                "role": trigger.role,
                "onsetMs": onset_ms,
                "tempoBpm": tempo_bpm,
            }
        )

    trigger_two = next(row for row in trigger_rows if row["id"] == 2)
    offset_ms = round(11912.0 - float(trigger_two["onsetMs"]), 3)

    plans: list[dict[str, Any]] = []
    for index, trigger in enumerate(trigger_rows):
        file_start_ms = round(float(trigger["onsetMs"]) + offset_ms, 3)
        if trigger["id"] == 1:
            next_trigger = trigger_rows[index + 1]
            fade_out_ms = two_beats_ms(float(next_trigger["tempoBpm"]))
            file_start_ms = FIRST_TRIGGER_START_MS
            file_end_ms = round(float(next_trigger["onsetMs"]) + offset_ms + fade_out_ms, 3)
            timing_rule = "trigger_1_fixed_start_to_trigger_2_plus_two_beats"
        elif index < len(trigger_rows) - 1:
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
                "measureToken": str(trigger["measureToken"]),
                "scoreMeasureOrdinal": int(trigger["scoreMeasureOrdinal"]),
                "position": str(trigger["position"]),
                "scoreLabel": str(trigger["scoreLabel"]),
                "role": str(trigger["role"]),
                "onsetMilliseconds": trigger["onsetMs"],
                "tempoBpm": trigger["tempoBpm"],
                "sourceOffsetMs": offset_ms,
                "timingNote": (
                    "Tour-cut trigger bundle preserving full trigger identities 1, 2, 3, 4, 5, 8, 11, 12. "
                    "Trigger Point 2 remains anchored to 00:11.912. The tour-cut electronics master truncates "
                    "full Trigger 5, crossfades into truncated Trigger 8, then rejoins the original source at Trigger 11."
                ),
                "variants": variant_payload,
            }
        )

    trigger8_plan = next((plan for plan in plans if plan["id"] == 8), None)
    m38_4_entry = token_lookup.get("38.4")
    if trigger8_plan is not None and m38_4_entry is not None:
        trigger8_onset_ms = float(trigger8_plan["onsetMilliseconds"])
        trigger8_end_ms = round(float(m38_4_entry["start_seconds"]) * 1000.0, 3)
        trigger8_duration_ms = round(trigger8_end_ms - trigger8_onset_ms, 3)
        trigger8_tempo_bpm = float(trigger8_plan["tempoBpm"])
        if trigger8_duration_ms <= 0:
            raise ValueError(
                f"Trigger 8 concrete window is invalid: {trigger8_duration_ms} ms"
            )

        concrete_variants: dict[str, dict[str, Any]] = {}
        for part_variant in PART_CONCRETE_VARIANTS:
            source_path = MUSIQUE_CONCRETE_SOURCE_ROOT / part_variant.source_name
            if not source_path.exists():
                raise FileNotFoundError(source_path)

            source_duration = ffprobe_duration_ms(source_path)
            clip_end_ms = min(trigger8_duration_ms, source_duration)
            fade_in_ms = min(beat_ms(trigger8_tempo_bpm, TP8_CONCRETE_FADE_IN_BEATS), clip_end_ms)
            fade_out_ms = min(beat_ms(trigger8_tempo_bpm, TP8_CONCRETE_FADE_OUT_BEATS), clip_end_ms)
            concrete_variants[part_variant.part_key] = {
                "sample": part_concrete_asset_key(8, part_variant),
                "channelMode": "part_track",
                "sourceFile": str(source_path.relative_to(ROOT)),
                "sourceStartMs": 0.0,
                "sourceEndMs": clip_end_ms,
                "durationMs": clip_end_ms,
                "fadeInMs": fade_in_ms,
                "fadeOutMs": fade_out_ms,
                "timingRule": "tp8_part_specific_concrete_fade_in_to_m38_4_downbeat",
                "designNote": (
                    f"{part_variant.label} receives its own musique-concrete strand at Trigger 8. "
                    "The strand blooms in over the first two beats and is fully faded out by M38.4 beat 1."
                ),
            }

        trigger8_plan["partVariants"] = concrete_variants
        trigger8_plan["timingNote"] = (
            trigger8_plan["timingNote"]
            + " Trigger 8 is a deliberate exception: six independent musique-concrete stems are assigned "
            + "to the six light-staff parts and each is forced to end at M38.4 beat 1."
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

        for part_variant in PART_CONCRETE_VARIANTS:
            payload = plan.get("partVariants", {}).get(part_variant.part_key)
            if payload is None:
                continue
            render_passthrough_variant(
                source_path=ROOT / payload["sourceFile"],
                output_path=part_concrete_output_path(plan["id"], part_variant),
                start_ms=float(payload["sourceStartMs"]),
                end_ms=float(payload["sourceEndMs"]),
                fade_in_ms=float(payload["fadeInMs"]),
                fade_out_ms=float(payload["fadeOutMs"]),
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
        "sourceFile": str(CUT_SOURCE_MP3.relative_to(ROOT)),
        "fullSourceFile": str(FULL_SOURCE_MP3.relative_to(ROOT)),
        "sourceDurationMs": source_duration_ms,
        "syncReference": str(SYNC_REFERENCE_PATH.relative_to(ROOT)),
        "triggerPointSource": str(TRIGGER_POINT_SOURCE.relative_to(ROOT)),
        "scoreMusicXml": str(CUT_SCORE_XML.relative_to(ROOT)),
        "flutterAssetRoot": str(FLUTTER_ASSET_ROOT.relative_to(ROOT)),
        "triggerPointCount": len(plans),
        "anchorOffsetMs": offset_ms,
        "fadeInMs": FADE_IN_MS,
        "firstTriggerStartMs": FIRST_TRIGGER_START_MS,
        "specialPartSpecificTriggerIds": [
            plan["id"] for plan in plans if plan.get("partVariants")
        ],
        "tailRule": "Each clip ends 2 beats after the next trigger point in the tour-cut timeline and fades across those final 2 beats.",
        "cutDefinition": "Keep full trigger identities 1, 2, 3, 4, 5, 8, 11, 12. Measures 38-41 are relabeled as 38 / 38.2 / 38.3 / 38.4 in the cut score. The electronics master truncates full Trigger 5, crossfades for 1 beat into full Trigger 8, then rejoins the source at full Trigger 11.",
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
                "measureToken",
                "measure",
                "scoreMeasureOrdinal",
                "position",
                "tempoBpm",
                "assignmentScope",
                "assignmentKey",
                "channelMode",
                "sourceFile",
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
                        "measureToken": plan["measureToken"],
                        "measure": plan["measure"],
                        "scoreMeasureOrdinal": plan["scoreMeasureOrdinal"],
                        "position": plan["position"],
                        "tempoBpm": plan["tempoBpm"],
                        "assignmentScope": "choir_family",
                        "assignmentKey": variant_key,
                        "channelMode": variant_payload["channelMode"],
                        "sourceFile": manifest["sourceFile"],
                        "sourceStartMs": variant_payload["sourceStartMs"],
                        "sourceEndMs": variant_payload["sourceEndMs"],
                        "durationMs": variant_payload["durationMs"],
                        "fadeInMs": variant_payload["fadeInMs"],
                        "fadeOutMs": variant_payload["fadeOutMs"],
                        "sample": variant_payload["sample"],
                    }
                )
            for part_key, variant_payload in plan.get("partVariants", {}).items():
                writer.writerow(
                    {
                        "id": plan["id"],
                        "scoreLabel": plan["scoreLabel"],
                        "measureToken": plan["measureToken"],
                        "measure": plan["measure"],
                        "scoreMeasureOrdinal": plan["scoreMeasureOrdinal"],
                        "position": plan["position"],
                        "tempoBpm": plan["tempoBpm"],
                        "assignmentScope": "light_staff",
                        "assignmentKey": part_key,
                        "channelMode": variant_payload["channelMode"],
                        "sourceFile": variant_payload.get("sourceFile", ""),
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
            "Tour-cut trigger bundle preserving full-version trigger identities 1, 2, 3, 4, 5, 8, 11, 12. "
            "Measures 38-41 are relabeled as 38 / 38.2 / 38.3 / 38.4, with Trigger 8 landing at 38.3. "
            "Trigger Point 2 remains locked to 00:11.912 in the tour-cut electronics master. "
            "The master truncates Trigger 5, crossfades into Trigger 8, and rejoins the source at Trigger 11. "
            "Trigger Point 1 starts at 00:02.000 in the file. All later clips start at their beat-mapped tour-cut onsets and end 2 beats after the next surviving trigger."
        ),
        "eventCount": len(plans),
        "generated": generated_at,
        "scoreMusicXml": str(CUT_SCORE_XML.relative_to(ROOT)),
        "electronicsSource": str(CUT_SOURCE_MP3.relative_to(ROOT)),
        "electronicsSyncReference": str(SYNC_REFERENCE_PATH.relative_to(ROOT)),
        "electronicsManifest": str(MANIFEST_JSON_PATH.relative_to(ROOT)),
        "electronicsGenerated": generated_at,
        "events": [
            {
                "id": plan["id"],
                "measure": plan["measure"],
                "measureToken": plan["measureToken"],
                "scoreMeasureOrdinal": plan["scoreMeasureOrdinal"],
                "position": plan["position"],
                "scoreLabel": plan["scoreLabel"],
                "timingNote": plan["timingNote"],
                "electronics": plan["variants"],
                "electronicsByPart": plan.get("partVariants", {}),
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
            "Render the tour-cut choir-part-specific electronics trigger assets "
            "and replace the runtime recipe bundles."
        )
    )
    parser.add_argument(
        "--skip-render",
        action="store_true",
        help="Update manifests and recipe bundles without re-rendering MP3 assets.",
    )
    parser.add_argument(
        "--skip-cut-source",
        action="store_true",
        help="Reuse the existing tour-cut electronics master if it already exists.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    for path in (
        FULL_SOURCE_MP3,
        FULL_SCORE_XML,
        CUT_SCORE_XML,
        TRIGGER_POINT_SOURCE,
        MUSIQUE_CONCRETE_SOURCE_ROOT,
    ):
        if not path.exists():
            raise FileNotFoundError(path)

    _, full_token_lookup, _ = build_measure_token_map(FULL_SCORE_XML)
    _, cut_token_lookup, _ = build_measure_token_map(CUT_SCORE_XML)
    trigger_specs = load_trigger_specs(TRIGGER_POINT_SOURCE)

    if not args.skip_render and not args.skip_cut_source:
        render_cut_source(
            full_source_path=FULL_SOURCE_MP3,
            output_path=CUT_SOURCE_MP3,
            full_token_lookup=full_token_lookup,
            cut_token_lookup=cut_token_lookup,
            trigger_specs=trigger_specs,
        )

    if not CUT_SOURCE_MP3.exists():
        raise FileNotFoundError(CUT_SOURCE_MP3)

    source_duration_ms = ffprobe_duration_ms(CUT_SOURCE_MP3)
    plans, offset_ms = build_trigger_plans(
        token_lookup=cut_token_lookup,
        source_duration_ms=source_duration_ms,
        trigger_specs=trigger_specs,
    )
    generated_at = iso_now()

    if not args.skip_render:
        clear_output_root(FLUTTER_ASSET_ROOT)
        render_assets(source_path=CUT_SOURCE_MP3, plans=plans)

    manifest = build_manifest(
        generated_at=generated_at,
        source_duration_ms=source_duration_ms,
        offset_ms=offset_ms,
        plans=plans,
    )
    write_manifest(manifest)
    write_recipe_copies(generated_at=generated_at, plans=plans)

    part_specific_asset_count = sum(
        len(plan.get("partVariants", {})) for plan in plans
    )
    print(f"Rendered {len(plans) * len(CHOIR_VARIANTS) + part_specific_asset_count} assets")
    print(f"Tour-cut source: {CUT_SOURCE_MP3.relative_to(ROOT)}")
    print(f"Manifest: {MANIFEST_JSON_PATH.relative_to(ROOT)}")
    print(f"Recipe copies updated: {len(RECIPE_COPY_PATHS)}")


if __name__ == "__main__":
    main()
