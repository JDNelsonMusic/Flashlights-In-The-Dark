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
TP5_TOTAL_BEATS = 26.0
TP5_BASE_BEATS = 12.0
TP5_BASE_FADE_OUT_BEATS = 4.0
TP5_CONCRETE_START_BEAT = 5.0
TP5_CONCRETE_END_BEAT = 24.0
TP5_CONCRETE_FADE_IN_BEATS = 4.0
TP5_CONCRETE_FADE_OUT_BEATS = 4.0
TP5_REENTRY_START_BEAT = 9.0
TP5_REENTRY_FADE_IN_BEATS = 14.0
TP5_REENTRY_FADE_OUT_BEATS = 2.0
TP5_REENTRY_SOURCE_START_MEASURE = "100"
TP5_REENTRY_SOURCE_END_MEASURE = "104"


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


def part_variant_asset_key(trigger_id: int, variant: PartConcreteVariant) -> str:
    return (
        "available-sounds/electronics-trigger-clips/part-specific/"
        f"{variant.directory}/electronics-trigger-{trigger_id:02d}-{variant.directory}-tour-cut-composite.mp3"
    )


def part_variant_output_path(trigger_id: int, variant: PartConcreteVariant) -> Path:
    return ROOT / "flashlights_client" / part_variant_asset_key(trigger_id, variant)


def choir_variant_for_part(part_key: str) -> ChoirVariant:
    if part_key.startswith("soprano"):
        return CHOIR_VARIANTS[0]
    if part_key.startswith("alto"):
        return CHOIR_VARIANTS[1]
    return CHOIR_VARIANTS[2]


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


def render_tp5_tour_cut_part_variant(
    *,
    full_source_path: Path,
    concrete_source_path: Path,
    output_path: Path,
    base_channel_expression: str,
    base_start_ms: float,
    reentry_start_ms: float,
    reentry_end_ms: float,
    total_duration_ms: float,
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    beat_duration_ms = beat_ms(72.0)
    base_duration_ms = round(beat_duration_ms * TP5_BASE_BEATS, 3)
    base_fade_out_ms = round(beat_duration_ms * TP5_BASE_FADE_OUT_BEATS, 3)
    base_fade_out_start_ms = round(base_duration_ms - base_fade_out_ms, 3)

    concrete_delay_ms = round(beat_duration_ms * (TP5_CONCRETE_START_BEAT - 1.0), 3)
    concrete_duration_ms = round(
        beat_duration_ms * (TP5_CONCRETE_END_BEAT - TP5_CONCRETE_START_BEAT + 1.0),
        3,
    )
    concrete_fade_out_start_ms = round(
        concrete_duration_ms - beat_duration_ms * TP5_CONCRETE_FADE_OUT_BEATS,
        3,
    )

    reentry_delay_ms = round(beat_duration_ms * (TP5_REENTRY_START_BEAT - 1.0), 3)
    reentry_duration_ms = round(reentry_end_ms - reentry_start_ms, 3)
    reentry_fade_in_ms = round(beat_duration_ms * TP5_REENTRY_FADE_IN_BEATS, 3)
    reentry_fade_out_ms = round(beat_duration_ms * TP5_REENTRY_FADE_OUT_BEATS, 3)
    reentry_fade_out_start_ms = round(reentry_duration_ms - reentry_fade_out_ms, 3)

    filter_graph = (
        f"[0:a]atrim=start={base_start_ms / 1000.0:.6f}:end={(base_start_ms + base_duration_ms) / 1000.0:.6f},"
        "asetpts=PTS-STARTPTS,"
        f"pan=mono|{base_channel_expression},"
        f"afade=t=in:st=0:d={FADE_IN_MS / 1000.0:.6f},"
        f"afade=t=out:st={base_fade_out_start_ms / 1000.0:.6f}:d={base_fade_out_ms / 1000.0:.6f}[base];"
        f"[1:a]atrim=start=0:end={concrete_duration_ms / 1000.0:.6f},"
        "asetpts=PTS-STARTPTS,"
        "pan=mono|c0=0.5*c0+0.5*c1,"
        f"afade=t=in:st=0:d={(beat_duration_ms * TP5_CONCRETE_FADE_IN_BEATS) / 1000.0:.6f},"
        f"afade=t=out:st={concrete_fade_out_start_ms / 1000.0:.6f}:d={(beat_duration_ms * TP5_CONCRETE_FADE_OUT_BEATS) / 1000.0:.6f},"
        f"adelay={int(round(concrete_delay_ms))}:all=1[concrete];"
        f"[0:a]atrim=start={reentry_start_ms / 1000.0:.6f}:end={reentry_end_ms / 1000.0:.6f},"
        "asetpts=PTS-STARTPTS,"
        f"pan=mono|{base_channel_expression},"
        f"afade=t=in:st=0:d={reentry_fade_in_ms / 1000.0:.6f},"
        f"afade=t=out:st={reentry_fade_out_start_ms / 1000.0:.6f}:d={reentry_fade_out_ms / 1000.0:.6f},"
        f"adelay={int(round(reentry_delay_ms))}:all=1[reentry];"
        f"[base][concrete][reentry]amix=inputs=3:normalize=0:dropout_transition=0,"
        f"apad=whole_dur={total_duration_ms / 1000.0:.6f},"
        f"atrim=duration={total_duration_ms / 1000.0:.6f},"
        "alimiter=limit=0.97[out]"
    )

    subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-y",
            "-i",
            str(full_source_path),
            "-i",
            str(concrete_source_path),
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


def trigger_source_onset_ms(
    token_lookup: dict[str, dict[str, Any]],
    trigger: TriggerPointSpec,
    offset_ms: float,
) -> float:
    onset_ms, _, _ = trigger_onset_ms(
        token_lookup,
        TriggerPointSpec(
            id=trigger.id,
            measure_token=trigger.source_measure_token,
            measure=trigger.source_measure,
            position_label=trigger.position_label,
            score_label=trigger.score_label,
            role=trigger.role,
            source_measure_token=trigger.source_measure_token,
            source_measure=trigger.source_measure,
        ),
    )
    return round(onset_ms + offset_ms, 3)


def build_trigger_plans(
    *,
    cut_token_lookup: dict[str, dict[str, Any]],
    full_token_lookup: dict[str, dict[str, Any]],
    source_duration_ms: float,
    trigger_specs: list[TriggerPointSpec],
) -> tuple[list[dict[str, Any]], float]:
    trigger_rows: list[dict[str, Any]] = []
    for trigger in trigger_specs:
        onset_ms, tempo_bpm, ordinal = trigger_onset_ms(cut_token_lookup, trigger)
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
        trigger_spec = trigger_specs[index]
        timing_note = (
            "Tour-cut trigger bundle preserving full trigger identities 1, 2, 3, 4, 5, 11, 12. "
            "Trigger Point 2 remains anchored to 00:11.912. Trigger 5 is a custom 26-beat composite: "
            "the opening electronics speak for 12 beats, six musique-concrete strands bloom from beats 5-24, "
            "and a mm100-103 preview enters on beats 9-26 before Trigger 11 takes over at M104 beat 1."
        )

        variant_payload: dict[str, dict[str, Any]] = {}
        part_variants: dict[str, dict[str, Any]] = {}

        if trigger["id"] == 5:
            beat_duration_ms = beat_ms(float(trigger["tempoBpm"]))
            total_duration_ms = round(beat_duration_ms * TP5_TOTAL_BEATS, 3)
            base_start_ms = trigger_source_onset_ms(
                full_token_lookup,
                trigger_spec,
                offset_ms,
            )
            base_end_ms = round(base_start_ms + beat_duration_ms * TP5_BASE_BEATS, 3)
            reentry_start_ms = round(
                float(full_token_lookup[TP5_REENTRY_SOURCE_START_MEASURE]["start_seconds"]) * 1000.0
                + offset_ms,
                3,
            )
            reentry_end_ms = round(
                float(full_token_lookup[TP5_REENTRY_SOURCE_END_MEASURE]["start_seconds"]) * 1000.0
                + offset_ms
                + beat_duration_ms * TP5_REENTRY_FADE_OUT_BEATS,
                3,
            )

            for part_variant in PART_CONCRETE_VARIANTS:
                choir_variant = choir_variant_for_part(part_variant.part_key)
                concrete_source = MUSIQUE_CONCRETE_SOURCE_ROOT / part_variant.source_name
                if not concrete_source.exists():
                    raise FileNotFoundError(concrete_source)

                part_variants[part_variant.part_key] = {
                    "sample": part_variant_asset_key(5, part_variant),
                    "channelMode": "part_track",
                    "sourceFile": "composite:full_electronics+musique_concrete+mm100_103",
                    "sourceStartMs": 0.0,
                    "sourceEndMs": total_duration_ms,
                    "durationMs": total_duration_ms,
                    "fadeInMs": FADE_IN_MS,
                    "fadeOutMs": beat_duration_ms * TP5_REENTRY_FADE_OUT_BEATS,
                    "timingRule": "tp5_custom_26_beat_tour_cut_composite",
                    "designNote": (
                        f"{part_variant.label} receives a dedicated TP5 composite: "
                        "12 beats of M36 electronics, a unique musique-concrete strand from beats 5-24, "
                        "and the mm100-103 preview from beats 9-26."
                    ),
                    "renderMode": "tp5_part_mix",
                    "baseChannelExpression": choir_variant.pan_expression,
                    "baseStartMs": base_start_ms,
                    "baseEndMs": base_end_ms,
                    "concreteSourceFile": str(concrete_source.relative_to(ROOT)),
                    "concreteStartBeat": TP5_CONCRETE_START_BEAT,
                    "concreteEndBeat": TP5_CONCRETE_END_BEAT,
                    "reentrySourceStartMs": reentry_start_ms,
                    "reentrySourceEndMs": reentry_end_ms,
                }
        else:
            file_start_ms = trigger_source_onset_ms(
                full_token_lookup,
                trigger_spec,
                offset_ms,
            )
            if trigger["id"] == 1:
                next_trigger = trigger_rows[index + 1]
                next_trigger_spec = trigger_specs[index + 1]
                fade_out_ms = two_beats_ms(float(next_trigger["tempoBpm"]))
                file_start_ms = FIRST_TRIGGER_START_MS
                file_end_ms = round(
                    trigger_source_onset_ms(full_token_lookup, next_trigger_spec, offset_ms)
                    + fade_out_ms,
                    3,
                )
                timing_rule = "trigger_1_fixed_start_to_trigger_2_plus_two_beats"
            elif index < len(trigger_rows) - 1:
                next_trigger = trigger_rows[index + 1]
                next_trigger_spec = trigger_specs[index + 1]
                fade_out_ms = two_beats_ms(float(next_trigger["tempoBpm"]))
                file_end_ms = round(
                    trigger_source_onset_ms(full_token_lookup, next_trigger_spec, offset_ms)
                    + fade_out_ms,
                    3,
                )
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

            for variant in CHOIR_VARIANTS:
                variant_payload[variant.key] = {
                    "sample": variant_asset_key(int(trigger["id"]), variant),
                    "channelMode": variant.channel_mode,
                    "sourceFile": str(FULL_SOURCE_MP3.relative_to(ROOT)),
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
                "timingNote": timing_note,
                "variants": variant_payload,
                "partVariants": part_variants,
            }
        )

    return plans, offset_ms


def render_assets(
    *,
    plans: list[dict[str, Any]],
) -> None:
    for plan in plans:
        for variant in CHOIR_VARIANTS:
            payload = plan["variants"].get(variant.key)
            if payload is None:
                continue
            render_variant(
                source_path=ROOT / payload.get("sourceFile", str(FULL_SOURCE_MP3.relative_to(ROOT))),
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
            if payload.get("renderMode") == "tp5_part_mix":
                render_tp5_tour_cut_part_variant(
                    full_source_path=FULL_SOURCE_MP3,
                    concrete_source_path=ROOT / payload["concreteSourceFile"],
                    output_path=part_variant_output_path(plan["id"], part_variant),
                    base_channel_expression=str(payload["baseChannelExpression"]),
                    base_start_ms=float(payload["baseStartMs"]),
                    reentry_start_ms=float(payload["reentrySourceStartMs"]),
                    reentry_end_ms=float(payload["reentrySourceEndMs"]),
                    total_duration_ms=float(payload["durationMs"]),
                )
            else:
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
        "sourceFile": str(FULL_SOURCE_MP3.relative_to(ROOT)),
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
        "tailRule": "Standard clips end 2 beats after the next surviving trigger point. Trigger 5 is a custom 26-beat composite and overlaps Trigger 11 by 2 beats.",
        "cutDefinition": "Keep full trigger identities 1, 2, 3, 4, 5, 11, 12. Measures 38-41 are relabeled as 38 / 38.2 / 38.3 / 38.4 in the cut score. Trigger 5 becomes a custom bridge composite carrying 12 beats of its own source, six musique-concrete entries from beats 5-24, and a mm100-103 preview from beats 9-26 before Trigger 11 reenters at M104 beat 1.",
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
            "Tour-cut trigger bundle preserving full-version trigger identities 1, 2, 3, 4, 5, 11, 12. "
            "Measures 38-41 are relabeled as 38 / 38.2 / 38.3 / 38.4. "
            "Trigger Point 2 remains locked to 00:11.912 in the tour-cut electronics master. "
            "Trigger Point 5 is now a custom 26-beat tour-cut composite: its own electronics sound for 12 beats, "
            "six musique-concrete strands enter on beats 5-24, and a mm100-103 layer crescendos across beats 9-26. "
            "Trigger Point 11 stays at M104 beat 1 and overlaps TP5 by 2 beats. Trigger Point 1 starts at 00:02.000 in the file."
        ),
        "eventCount": len(plans),
        "generated": generated_at,
        "scoreMusicXml": str(CUT_SCORE_XML.relative_to(ROOT)),
        "electronicsSource": str(FULL_SOURCE_MP3.relative_to(ROOT)),
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
    source_duration_ms = ffprobe_duration_ms(FULL_SOURCE_MP3)
    plans, offset_ms = build_trigger_plans(
        cut_token_lookup=cut_token_lookup,
        full_token_lookup=full_token_lookup,
        source_duration_ms=source_duration_ms,
        trigger_specs=trigger_specs,
    )
    generated_at = iso_now()

    if not args.skip_render:
        clear_output_root(FLUTTER_ASSET_ROOT)
        render_assets(plans=plans)

    manifest = build_manifest(
        generated_at=generated_at,
        source_duration_ms=source_duration_ms,
        offset_ms=offset_ms,
        plans=plans,
    )
    write_manifest(manifest)
    write_recipe_copies(generated_at=generated_at, plans=plans)

    choir_asset_count = sum(len(plan.get("variants", {})) for plan in plans)
    part_specific_asset_count = sum(len(plan.get("partVariants", {})) for plan in plans)
    print(f"Rendered {choir_asset_count + part_specific_asset_count} assets")
    print(f"Primary source: {FULL_SOURCE_MP3.relative_to(ROOT)}")
    print(f"Manifest: {MANIFEST_JSON_PATH.relative_to(ROOT)}")
    print(f"Recipe copies updated: {len(RECIPE_COPY_PATHS)}")


if __name__ == "__main__":
    main()
