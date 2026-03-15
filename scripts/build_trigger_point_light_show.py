#!/usr/bin/env python3
"""Build the 12-trigger flashlight choreography for the reduced score workflow.

This script injects a six-staff torch plan into every canonical event recipe copy.
The choreography is authored against the current reduced trigger-point score and
the trigger-onset timing manifest already used for the electronics slices.
"""

from __future__ import annotations

import json
from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
import xml.etree.ElementTree as ET


REPO_ROOT = Path(__file__).resolve().parents[1]
TRIGGER_MANIFEST_PATH = REPO_ROOT / "docs/protools-housekeeping/electronics_trigger_assets.json"
MUSICXML_PATH = REPO_ROOT / "flashlights_client/assets/FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml"
LIGHT_SHOW_MANIFEST_PATH = REPO_ROOT / "docs/score-study/twelve_trigger_light_show.json"

RECIPE_COPY_PATHS = [
    REPO_ROOT / "Flashlights-ITD_EventRecipes_4_2026_0309/event_recipes.json",
    REPO_ROOT / "FlashlightsInTheDark_MacOS/Resources/event_recipes.json",
    REPO_ROOT / "flashlights_client/assets/event_recipes.json",
]

PART_ORDER = [
    "soprano_l1",
    "soprano_l2",
    "tenor_l",
    "bass_l",
    "alto_l2",
    "alto_l1",
]

PART_LABELS = {
    "soprano_l1": "Sop-L1",
    "soprano_l2": "Sop-L2",
    "tenor_l": "Ten-L",
    "bass_l": "Bass-L",
    "alto_l2": "Alto-L2",
    "alto_l1": "Alto-L1",
}

TP12_FIXED_DURATION_MS = 98000.0
TP12_TEMPO_BPM = 72.0
TP12_VOICE_MAP = {
    "soprano_l1": ("P4", "1"),
    "soprano_l2": ("P4", "2"),
    "alto_l1": ("P5", "1"),
    "alto_l2": ("P5", "2"),
    "tenor_l": ("P6", "1"),
    "bass_l": ("P6", "2"),
}
TP12_BASE_LEVELS = {
    "soprano_l1": 0.22,
    "soprano_l2": 0.24,
    "tenor_l": 0.28,
    "bass_l": 0.30,
    "alto_l2": 0.20,
    "alto_l1": 0.18,
}
TP12_SUMMARIES = {
    "soprano_l1": "Every flash is locked to Sop-L1 note onsets, leaving a fragile upper-left residue.",
    "soprano_l2": "Sop-L2 answers strictly on its own entrances, never drifting off the score rhythm.",
    "tenor_l": "Tenor keeps the strongest note-synchronous core through the final section.",
    "bass_l": "Bass traces each onset with the deepest synchronized low flash.",
    "alto_l2": "Alto-L2 articulates the ending as a right-middle rhythmic echo.",
    "alto_l1": "Alto-L1 remains the faintest note-synchronous edge of the final fade.",
}


@dataclass(frozen=True)
class PartPlan:
    summary: str
    motion: str
    peak_level: float
    points: list[tuple[float, float]]


@dataclass(frozen=True)
class EventPlan:
    summary: str
    score_dynamics: str
    design_tags: list[str]
    duration_scale: float | None
    fixed_duration_ms: float | None
    parts: dict[str, PartPlan]


def _scale_points(duration_ms: float, points: list[tuple[float, float]]) -> list[dict[str, float]]:
    keyframes: list[dict[str, float]] = []
    for fraction, level in points:
        at_ms = round(duration_ms * fraction, 3)
        keyframes.append({"atMs": at_ms, "level": round(max(0.0, min(level, 1.0)), 3)})
    if not keyframes:
        return [{"atMs": 0.0, "level": 0.0}]
    if keyframes[0]["atMs"] != 0.0:
        keyframes.insert(0, {"atMs": 0.0, "level": 0.0})
    if keyframes[-1]["atMs"] != round(duration_ms, 3):
        keyframes.append({"atMs": round(duration_ms, 3), "level": 0.0})
    else:
        keyframes[-1]["level"] = 0.0
    return keyframes


def _dedupe_fraction_points(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    deduped: dict[float, float] = {}
    for fraction, level in sorted(points, key=lambda item: item[0]):
        key = round(fraction, 6)
        deduped[key] = max(level, deduped.get(key, 0.0))
    return [(fraction, deduped[fraction]) for fraction in sorted(deduped)]


def _collect_tp12_voice_onsets() -> dict[str, list[dict[str, float | bool]]]:
    root = ET.parse(MUSICXML_PATH).getroot()
    parts = {part.attrib["id"]: part for part in root.findall("part")}
    result: dict[str, list[dict[str, float | bool]]] = {}
    ms_per_beat = 60000.0 / TP12_TEMPO_BPM

    for part_key, (part_id, target_voice) in TP12_VOICE_MAP.items():
        part = parts[part_id]
        current_divisions = 1
        beats_since_115 = 0.0
        captured: list[dict[str, float | bool]] = []

        for measure in part.findall("measure"):
            measure_number = int(measure.attrib["number"])
            attrs = measure.find("attributes")
            if attrs is not None and attrs.findtext("divisions"):
                current_divisions = int(attrs.findtext("divisions"))

            if measure_number < 115:
                continue

            position_divisions = 0
            max_position_divisions = 0
            last_note_onset_divisions = 0

            for child in measure:
                if child.tag == "attributes":
                    if child.findtext("divisions"):
                        current_divisions = int(child.findtext("divisions"))
                    continue

                if child.tag == "backup":
                    position_divisions -= int(child.findtext("duration", "0"))
                    continue

                if child.tag == "forward":
                    position_divisions += int(child.findtext("duration", "0"))
                    max_position_divisions = max(max_position_divisions, position_divisions)
                    continue

                if child.tag != "note":
                    continue

                duration = int(child.findtext("duration", "0"))
                is_chord = child.find("chord") is not None
                onset_divisions = last_note_onset_divisions if is_chord else position_divisions
                voice = child.findtext("voice", "1")
                is_rest = child.find("rest") is not None

                if voice == target_voice and not is_rest and not is_chord:
                    onset_beats = beats_since_115 + (onset_divisions / current_divisions)
                    captured.append(
                        {
                            "onsetMs": round(onset_beats * ms_per_beat, 3),
                            "measureDownbeat": onset_divisions == 0,
                        }
                    )

                if not is_chord:
                    last_note_onset_divisions = position_divisions
                    position_divisions += duration
                    max_position_divisions = max(max_position_divisions, position_divisions)

            beats_since_115 += max_position_divisions / current_divisions

        result[part_key] = captured

    return result


def _build_tp12_parts() -> dict[str, PartPlan]:
    onset_map = _collect_tp12_voice_onsets()
    parts: dict[str, PartPlan] = {}

    for part_key in PART_ORDER:
        records = onset_map[part_key]
        base_peak = TP12_BASE_LEVELS[part_key]
        points: list[tuple[float, float]] = [(0.0, 0.0)]

        for index, record in enumerate(records):
            onset_ms = float(record["onsetMs"])
            measure_downbeat = bool(record["measureDownbeat"])
            next_onset_ms = (
                float(records[index + 1]["onsetMs"])
                if index + 1 < len(records)
                else TP12_FIXED_DURATION_MS
            )
            gap_ms = max(180.0, next_onset_ms - onset_ms)
            peak_level = min(base_peak + (0.04 if measure_downbeat else 0.0), 0.34)
            tail_level = round(peak_level * 0.38, 3)
            settle_ms = min(gap_ms * 0.28, 220.0)
            release_ms = min(gap_ms * 0.62, 520.0)
            pre_ms = max(0.0, onset_ms - 18.0)
            points.append((pre_ms / TP12_FIXED_DURATION_MS, 0.0))
            points.append((onset_ms / TP12_FIXED_DURATION_MS, peak_level))
            points.append((min(TP12_FIXED_DURATION_MS, onset_ms + settle_ms) / TP12_FIXED_DURATION_MS, tail_level))
            points.append((min(TP12_FIXED_DURATION_MS, onset_ms + release_ms) / TP12_FIXED_DURATION_MS, 0.0))

        normalised = _dedupe_fraction_points(points)
        parts[part_key] = PartPlan(
            summary=TP12_SUMMARIES[part_key],
            motion="note-synchronous",
            peak_level=round(max(level for _, level in normalised), 3),
            points=normalised,
        )

    return parts


def _resolve_event_duration_ms(event_id: int, available_window_ms: float, plan: EventPlan) -> float:
    if plan.fixed_duration_ms is not None:
        return plan.fixed_duration_ms
    scale = plan.duration_scale if plan.duration_scale is not None else 0.92
    return round(available_window_ms * scale, 3)


def _build_event_plans() -> dict[int, EventPlan]:
    return {
        1: EventPlan(
            summary="Darkness loosens from stage left and crosses the ensemble as a first glint.",
            score_dynamics="Begin in darkness -> first emergence",
            design_tags=["left_to_right", "opening_glint", "ppp_to_p"],
            duration_scale=0.96,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan(
                    summary="Leads the first glint at the far-left edge.",
                    motion="lead-left",
                    peak_level=0.18,
                    points=[(0.00, 0.0), (0.10, 0.05), (0.26, 0.18), (0.48, 0.08), (0.78, 0.02), (1.00, 0.0)],
                ),
                "soprano_l2": PartPlan(
                    summary="Answers just right of the opening spark.",
                    motion="left-to-right",
                    peak_level=0.16,
                    points=[(0.00, 0.0), (0.18, 0.03), (0.36, 0.16), (0.58, 0.07), (0.84, 0.02), (1.00, 0.0)],
                ),
                "tenor_l": PartPlan(
                    summary="A low central ember wakes after the sopranos.",
                    motion="left-to-right",
                    peak_level=0.13,
                    points=[(0.00, 0.0), (0.28, 0.02), (0.50, 0.13), (0.70, 0.05), (1.00, 0.0)],
                ),
                "bass_l": PartPlan(
                    summary="Bass shadow arrives late and remains restrained.",
                    motion="left-to-right",
                    peak_level=0.11,
                    points=[(0.00, 0.0), (0.36, 0.01), (0.60, 0.11), (0.80, 0.04), (1.00, 0.0)],
                ),
                "alto_l2": PartPlan(
                    summary="A small right-side shimmer catches only at the end of the breath.",
                    motion="tail-answer",
                    peak_level=0.08,
                    points=[(0.00, 0.0), (0.50, 0.0), (0.74, 0.08), (0.90, 0.03), (1.00, 0.0)],
                ),
                "alto_l1": PartPlan(
                    summary="The far-right edge barely lights before the piece tips into Trigger 2.",
                    motion="tail-answer",
                    peak_level=0.06,
                    points=[(0.00, 0.0), (0.62, 0.0), (0.86, 0.06), (1.00, 0.0)],
                ),
            },
        ),
        2: EventPlan(
            summary="A strong forte shimmer courses left-to-right, then measures 11–19 fracture into faster irregular cross-ensemble flashes before the rebound.",
            score_dynamics="f",
            design_tags=["double_sweep", "forte_shimmer", "cross_stage", "stochastic_middle_band"],
            duration_scale=0.94,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan(
                    summary="Opens the first bright sweep, then breaks into fast left-biased stochastic flashes before reigniting.",
                    motion="left-right-stochastic-left",
                    peak_level=0.86,
                    points=[(0.00, 0.0), (0.05, 0.14), (0.14, 0.86), (0.28, 0.22), (0.40, 0.12), (0.44, 0.58), (0.47, 0.08), (0.52, 0.66), (0.55, 0.10), (0.60, 0.50), (0.63, 0.08), (0.68, 0.72), (0.72, 0.12), (0.76, 0.72), (0.90, 0.10), (1.00, 0.0)],
                ),
                "soprano_l2": PartPlan(
                    summary="Tracks the first sweep, then interlocks with Sop-L1 in faster uneven upper-left flickers.",
                    motion="left-right-stochastic-left",
                    peak_level=0.82,
                    points=[(0.00, 0.0), (0.08, 0.12), (0.18, 0.82), (0.32, 0.24), (0.42, 0.10), (0.46, 0.54), (0.49, 0.12), (0.53, 0.62), (0.57, 0.10), (0.61, 0.46), (0.66, 0.14), (0.71, 0.68), (0.75, 0.12), (0.80, 0.66), (0.92, 0.10), (1.00, 0.0)],
                ),
                "tenor_l": PartPlan(
                    summary="The center-left staff becomes a restless engine of irregular flashes across measures 11–19.",
                    motion="central-stochastic",
                    peak_level=0.78,
                    points=[(0.00, 0.0), (0.12, 0.10), (0.24, 0.78), (0.38, 0.26), (0.41, 0.14), (0.45, 0.60), (0.48, 0.08), (0.51, 0.74), (0.55, 0.12), (0.59, 0.52), (0.63, 0.08), (0.67, 0.70), (0.71, 0.10), (0.76, 0.56), (0.84, 0.58), (0.94, 0.08), (1.00, 0.0)],
                ),
                "bass_l": PartPlan(
                    summary="Bass anchors the stochastic section with the deepest irregular weight.",
                    motion="center-stochastic",
                    peak_level=0.74,
                    points=[(0.00, 0.0), (0.16, 0.08), (0.28, 0.74), (0.42, 0.18), (0.46, 0.58), (0.50, 0.10), (0.54, 0.72), (0.58, 0.12), (0.62, 0.48), (0.66, 0.08), (0.70, 0.64), (0.74, 0.18), (0.86, 0.54), (0.95, 0.07), (1.00, 0.0)],
                ),
                "alto_l2": PartPlan(
                    summary="Receives the first sweep, then snaps into quick right-side irregular replies.",
                    motion="rightward-stochastic",
                    peak_level=0.80,
                    points=[(0.00, 0.0), (0.22, 0.08), (0.34, 0.80), (0.40, 0.14), (0.45, 0.44), (0.49, 0.10), (0.55, 0.70), (0.59, 0.12), (0.64, 0.50), (0.68, 0.10), (0.73, 0.68), (0.78, 0.16), (0.84, 0.60), (0.94, 0.08), (1.00, 0.0)],
                ),
                "alto_l1": PartPlan(
                    summary="The far-right edge receives the bright wave last, then throws back fast irregular sparks before the return sweep.",
                    motion="right-edge-stochastic-rebound",
                    peak_level=0.88,
                    points=[(0.00, 0.0), (0.26, 0.06), (0.38, 0.88), (0.43, 0.12), (0.47, 0.52), (0.51, 0.08), (0.57, 0.76), (0.61, 0.10), (0.66, 0.56), (0.70, 0.08), (0.75, 0.72), (0.78, 0.76), (0.92, 0.10), (1.00, 0.0)],
                ),
            },
        ),
        3: EventPlan(
            summary="The forte glare breaks into a soft right-to-left drift with long dim tails.",
            score_dynamics="p",
            design_tags=["right_to_left", "soft_drift", "afterimage"],
            duration_scale=0.93,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan(
                    summary="Receives the last portion of the retreat and fades almost immediately.",
                    motion="receive",
                    peak_level=0.22,
                    points=[(0.00, 0.0), (0.48, 0.02), (0.66, 0.22), (0.82, 0.08), (1.00, 0.0)],
                ),
                "soprano_l2": PartPlan(
                    summary="Lights briefly after the altos, then falls back into dark.",
                    motion="receive",
                    peak_level=0.24,
                    points=[(0.00, 0.0), (0.36, 0.03), (0.56, 0.24), (0.76, 0.09), (1.00, 0.0)],
                ),
                "tenor_l": PartPlan(
                    summary="Carries the center of the decrescendo for the longest span.",
                    motion="center-carry",
                    peak_level=0.28,
                    points=[(0.00, 0.0), (0.24, 0.05), (0.44, 0.28), (0.62, 0.14), (0.82, 0.04), (1.00, 0.0)],
                ),
                "bass_l": PartPlan(
                    summary="A grounded low glow lingers beneath the receding wave.",
                    motion="low-anchor",
                    peak_level=0.26,
                    points=[(0.00, 0.0), (0.18, 0.04), (0.36, 0.26), (0.56, 0.16), (0.78, 0.05), (1.00, 0.0)],
                ),
                "alto_l2": PartPlan(
                    summary="Starts the retreat with a soft but clear right-side lead.",
                    motion="lead-right",
                    peak_level=0.30,
                    points=[(0.00, 0.0), (0.08, 0.08), (0.22, 0.30), (0.46, 0.12), (0.70, 0.04), (1.00, 0.0)],
                ),
                "alto_l1": PartPlan(
                    summary="The far-right edge speaks first, then withdraws the fastest.",
                    motion="lead-right",
                    peak_level=0.34,
                    points=[(0.00, 0.0), (0.04, 0.10), (0.18, 0.34), (0.36, 0.10), (0.58, 0.02), (1.00, 0.0)],
                ),
            },
        ),
        4: EventPlan(
            summary="A compact, compressed pulse ignites from the middle and flicks outward.",
            score_dynamics="p -> mp",
            design_tags=["center_out", "compressed_pulse", "brief"],
            duration_scale=0.90,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan(
                    summary="Catches the outermost left splash at the end of the pulse.",
                    motion="outer-splash",
                    peak_level=0.26,
                    points=[(0.00, 0.0), (0.54, 0.02), (0.72, 0.26), (0.88, 0.06), (1.00, 0.0)],
                ),
                "soprano_l2": PartPlan(
                    summary="Follows the central ignition with a short upper-left flicker.",
                    motion="outer-splash",
                    peak_level=0.30,
                    points=[(0.00, 0.0), (0.36, 0.04), (0.56, 0.30), (0.76, 0.08), (1.00, 0.0)],
                ),
                "tenor_l": PartPlan(
                    summary="Starts the pulse from the left side of the center pair.",
                    motion="center-start",
                    peak_level=0.40,
                    points=[(0.00, 0.0), (0.12, 0.10), (0.28, 0.40), (0.50, 0.12), (1.00, 0.0)],
                ),
                "bass_l": PartPlan(
                    summary="Completes the center ignition with a warm bass flash.",
                    motion="center-start",
                    peak_level=0.42,
                    points=[(0.00, 0.0), (0.14, 0.12), (0.30, 0.42), (0.48, 0.12), (1.00, 0.0)],
                ),
                "alto_l2": PartPlan(
                    summary="Receives the pulse on the right side a beat later.",
                    motion="outer-splash",
                    peak_level=0.30,
                    points=[(0.00, 0.0), (0.42, 0.04), (0.62, 0.30), (0.80, 0.08), (1.00, 0.0)],
                ),
                "alto_l1": PartPlan(
                    summary="The far-right edge blinks last, then drops instantly away.",
                    motion="outer-splash",
                    peak_level=0.24,
                    points=[(0.00, 0.0), (0.58, 0.02), (0.76, 0.24), (0.90, 0.05), (1.00, 0.0)],
                ),
            },
        ),
        5: EventPlan(
            summary="A moderate breath opens from the center and widens slowly toward both edges.",
            score_dynamics="mp",
            design_tags=["center_out", "breathing_arc", "moderate"],
            duration_scale=0.94,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan(
                    summary="Far-left soprano blooms only after the central pair has opened.",
                    motion="center-out",
                    peak_level=0.46,
                    points=[(0.00, 0.0), (0.34, 0.03), (0.50, 0.26), (0.68, 0.46), (0.84, 0.16), (1.00, 0.0)],
                ),
                "soprano_l2": PartPlan(
                    summary="Upper-left line broadens into a rounded secondary crest.",
                    motion="center-out",
                    peak_level=0.50,
                    points=[(0.00, 0.0), (0.24, 0.04), (0.40, 0.28), (0.58, 0.50), (0.80, 0.18), (1.00, 0.0)],
                ),
                "tenor_l": PartPlan(
                    summary="Tenor light initiates the breath with a steady middle glow.",
                    motion="center-origin",
                    peak_level=0.58,
                    points=[(0.00, 0.0), (0.08, 0.10), (0.20, 0.42), (0.38, 0.58), (0.64, 0.24), (1.00, 0.0)],
                ),
                "bass_l": PartPlan(
                    summary="Bass stays warm and weighted beneath the widening gesture.",
                    motion="center-origin",
                    peak_level=0.56,
                    points=[(0.00, 0.0), (0.10, 0.12), (0.22, 0.40), (0.40, 0.56), (0.66, 0.26), (1.00, 0.0)],
                ),
                "alto_l2": PartPlan(
                    summary="Right-middle altos open late and shine a little cleaner than the left edge.",
                    motion="center-out",
                    peak_level=0.48,
                    points=[(0.00, 0.0), (0.28, 0.04), (0.44, 0.26), (0.62, 0.48), (0.82, 0.17), (1.00, 0.0)],
                ),
                "alto_l1": PartPlan(
                    summary="The far-right edge closes the breath with the latest bloom.",
                    motion="center-out",
                    peak_level=0.44,
                    points=[(0.00, 0.0), (0.38, 0.02), (0.54, 0.22), (0.72, 0.44), (0.86, 0.14), (1.00, 0.0)],
                ),
            },
        ),
        6: EventPlan(
            summary="Suspended three-beat rocking shifts weight between the center and the stage edges.",
            score_dynamics="mp, suspended",
            design_tags=["pendulum", "three_beat", "suspension"],
            duration_scale=0.93,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan(
                    summary="Joins only on the leftward swing, then recedes.",
                    motion="pendulum-left",
                    peak_level=0.38,
                    points=[(0.00, 0.0), (0.18, 0.04), (0.30, 0.38), (0.46, 0.12), (0.64, 0.06), (0.78, 0.30), (0.92, 0.08), (1.00, 0.0)],
                ),
                "soprano_l2": PartPlan(
                    summary="Carries the upper-left lilt across both swings.",
                    motion="pendulum-left",
                    peak_level=0.44,
                    points=[(0.00, 0.0), (0.12, 0.08), (0.24, 0.44), (0.40, 0.16), (0.58, 0.08), (0.72, 0.34), (0.90, 0.10), (1.00, 0.0)],
                ),
                "tenor_l": PartPlan(
                    summary="Tenor drives the first swing and keeps the pulse coherent.",
                    motion="center-driver",
                    peak_level=0.54,
                    points=[(0.00, 0.0), (0.06, 0.12), (0.18, 0.54), (0.34, 0.20), (0.52, 0.10), (0.68, 0.40), (0.88, 0.10), (1.00, 0.0)],
                ),
                "bass_l": PartPlan(
                    summary="Bass gives the rocking motion its weight and deepest glow.",
                    motion="center-driver",
                    peak_level=0.56,
                    points=[(0.00, 0.0), (0.08, 0.12), (0.20, 0.56), (0.36, 0.22), (0.54, 0.12), (0.70, 0.42), (0.90, 0.10), (1.00, 0.0)],
                ),
                "alto_l2": PartPlan(
                    summary="Receives the rightward swing with a measured, late crest.",
                    motion="pendulum-right",
                    peak_level=0.42,
                    points=[(0.00, 0.0), (0.26, 0.04), (0.40, 0.42), (0.56, 0.14), (0.72, 0.10), (0.84, 0.30), (0.94, 0.06), (1.00, 0.0)],
                ),
                "alto_l1": PartPlan(
                    summary="The far-right edge lights only when the pendulum swings fully across.",
                    motion="pendulum-right",
                    peak_level=0.36,
                    points=[(0.00, 0.0), (0.34, 0.02), (0.48, 0.36), (0.62, 0.10), (0.80, 0.08), (0.90, 0.24), (0.98, 0.04), (1.00, 0.0)],
                ),
            },
        ),
        7: EventPlan(
            summary="A long exhale lets the glow travel right-to-left while steadily thinning toward piano.",
            score_dynamics="dim. -> p",
            design_tags=["right_to_left", "diminuendo", "long_exhale"],
            duration_scale=0.93,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan(
                    summary="Receives the final trace of the exhale as it disappears into stage left.",
                    motion="receive-fade",
                    peak_level=0.24,
                    points=[(0.00, 0.0), (0.56, 0.02), (0.72, 0.24), (0.86, 0.08), (1.00, 0.0)],
                ),
                "soprano_l2": PartPlan(
                    summary="Softens earlier than Trigger 5 and never quite returns to its former width.",
                    motion="receive-fade",
                    peak_level=0.28,
                    points=[(0.00, 0.0), (0.42, 0.03), (0.60, 0.28), (0.78, 0.10), (1.00, 0.0)],
                ),
                "tenor_l": PartPlan(
                    summary="Holds the center of the diminuendo before letting it go.",
                    motion="middle-fade",
                    peak_level=0.34,
                    points=[(0.00, 0.0), (0.26, 0.05), (0.44, 0.34), (0.62, 0.14), (0.82, 0.04), (1.00, 0.0)],
                ),
                "bass_l": PartPlan(
                    summary="Keeps a low ember alive longest, but only barely.",
                    motion="low-fade",
                    peak_level=0.30,
                    points=[(0.00, 0.0), (0.22, 0.05), (0.38, 0.30), (0.58, 0.16), (0.80, 0.05), (1.00, 0.0)],
                ),
                "alto_l2": PartPlan(
                    summary="Begins the exhale with the clearest right-side release.",
                    motion="lead-right",
                    peak_level=0.42,
                    points=[(0.00, 0.0), (0.06, 0.08), (0.18, 0.42), (0.38, 0.18), (0.60, 0.06), (1.00, 0.0)],
                ),
                "alto_l1": PartPlan(
                    summary="Starts brightest, then dims fastest as the energy drains away.",
                    motion="lead-right",
                    peak_level=0.46,
                    points=[(0.00, 0.0), (0.04, 0.10), (0.16, 0.46), (0.32, 0.16), (0.54, 0.05), (1.00, 0.0)],
                ),
            },
        ),
        8: EventPlan(
            summary="Separated search-beam gestures alternate between outer edges and the middle pair.",
            score_dynamics="restrained, searching",
            design_tags=["alternation", "outer_inner", "search_beams"],
            duration_scale=0.94,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan(
                    summary="Outer-left searches first and returns in the final glance.",
                    motion="outer-call",
                    peak_level=0.40,
                    points=[(0.00, 0.0), (0.08, 0.08), (0.20, 0.40), (0.34, 0.10), (0.58, 0.04), (0.76, 0.30), (0.92, 0.06), (1.00, 0.0)],
                ),
                "soprano_l2": PartPlan(
                    summary="Bridges the outer-left call back toward the center.",
                    motion="bridge",
                    peak_level=0.44,
                    points=[(0.00, 0.0), (0.16, 0.06), (0.30, 0.44), (0.46, 0.12), (0.68, 0.06), (0.84, 0.26), (0.96, 0.04), (1.00, 0.0)],
                ),
                "tenor_l": PartPlan(
                    summary="Takes the clearest middle search pass of the trigger.",
                    motion="inner-answer",
                    peak_level=0.52,
                    points=[(0.00, 0.0), (0.24, 0.08), (0.38, 0.52), (0.56, 0.14), (0.74, 0.08), (0.90, 0.22), (1.00, 0.0)],
                ),
                "bass_l": PartPlan(
                    summary="A low center glow answers the search pattern with extra weight.",
                    motion="inner-answer",
                    peak_level=0.50,
                    points=[(0.00, 0.0), (0.28, 0.08), (0.42, 0.50), (0.60, 0.16), (0.78, 0.08), (0.92, 0.20), (1.00, 0.0)],
                ),
                "alto_l2": PartPlan(
                    summary="Right-middle staff takes over late and arcs outward.",
                    motion="bridge",
                    peak_level=0.42,
                    points=[(0.00, 0.0), (0.30, 0.04), (0.46, 0.42), (0.64, 0.12), (0.82, 0.08), (0.94, 0.24), (1.00, 0.0)],
                ),
                "alto_l1": PartPlan(
                    summary="The far-right edge answers the far-left opening with its own brief search beam.",
                    motion="outer-call",
                    peak_level=0.38,
                    points=[(0.00, 0.0), (0.36, 0.02), (0.52, 0.38), (0.70, 0.10), (0.88, 0.26), (0.98, 0.04), (1.00, 0.0)],
                ),
            },
        ),
        9: EventPlan(
            summary="Quiet suspended lanterns appear in separate pockets rather than as a shared wave.",
            score_dynamics="p",
            design_tags=["isolated_pools", "hushed", "asymmetry"],
            duration_scale=0.93,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan(
                    summary="Barely-there high-left glow, almost a memory.",
                    motion="isolated",
                    peak_level=0.18,
                    points=[(0.00, 0.0), (0.24, 0.02), (0.40, 0.18), (0.56, 0.05), (1.00, 0.0)],
                ),
                "soprano_l2": PartPlan(
                    summary="A short reply above the left-middle, then silence.",
                    motion="isolated",
                    peak_level=0.20,
                    points=[(0.00, 0.0), (0.12, 0.02), (0.28, 0.20), (0.48, 0.06), (1.00, 0.0)],
                ),
                "tenor_l": PartPlan(
                    summary="The most stable pool of light sits in the tenor staff.",
                    motion="held-pool",
                    peak_level=0.28,
                    points=[(0.00, 0.0), (0.10, 0.08), (0.24, 0.28), (0.52, 0.10), (0.76, 0.04), (1.00, 0.0)],
                ),
                "bass_l": PartPlan(
                    summary="Bass glows later and lower, without ever matching tenor brightness.",
                    motion="held-pool",
                    peak_level=0.24,
                    points=[(0.00, 0.0), (0.24, 0.04), (0.42, 0.24), (0.60, 0.08), (0.84, 0.03), (1.00, 0.0)],
                ),
                "alto_l2": PartPlan(
                    summary="Right-middle light surfaces only briefly, like a distant response.",
                    motion="isolated",
                    peak_level=0.22,
                    points=[(0.00, 0.0), (0.34, 0.02), (0.52, 0.22), (0.68, 0.06), (1.00, 0.0)],
                ),
                "alto_l1": PartPlan(
                    summary="The far-right edge appears last and disappears first.",
                    motion="isolated",
                    peak_level=0.16,
                    points=[(0.00, 0.0), (0.48, 0.01), (0.62, 0.16), (0.76, 0.04), (1.00, 0.0)],
                ),
            },
        ),
        10: EventPlan(
            summary="A broad crescendo grows from scattered piano embers into the brightest cross-stage surge before Trigger 11.",
            score_dynamics="p -> ff",
            design_tags=["crescendo", "left_to_right", "climax_preparation"],
            duration_scale=0.98,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan(
                    summary="Begins the crescendo early on the far-left edge and returns at the final crest.",
                    motion="crescendo-sweep",
                    peak_level=0.96,
                    points=[(0.00, 0.0), (0.08, 0.08), (0.24, 0.26), (0.46, 0.52), (0.66, 0.82), (0.82, 0.96), (0.92, 0.20), (1.00, 0.0)],
                ),
                "soprano_l2": PartPlan(
                    summary="Takes the growing wave and keeps it shining through the center of the build.",
                    motion="crescendo-sweep",
                    peak_level=0.94,
                    points=[(0.00, 0.0), (0.12, 0.06), (0.28, 0.24), (0.50, 0.56), (0.70, 0.84), (0.86, 0.94), (0.94, 0.18), (1.00, 0.0)],
                ),
                "tenor_l": PartPlan(
                    summary="Center-left staff becomes the core engine of the crescendo.",
                    motion="center-build",
                    peak_level=0.98,
                    points=[(0.00, 0.0), (0.16, 0.06), (0.34, 0.28), (0.56, 0.62), (0.74, 0.90), (0.88, 0.98), (0.96, 0.18), (1.00, 0.0)],
                ),
                "bass_l": PartPlan(
                    summary="Bass reaches the deepest, fullest brightness at the top of the swell.",
                    motion="center-build",
                    peak_level=1.0,
                    points=[(0.00, 0.0), (0.18, 0.06), (0.36, 0.30), (0.58, 0.66), (0.76, 0.94), (0.90, 1.00), (0.96, 0.18), (1.00, 0.0)],
                ),
                "alto_l2": PartPlan(
                    summary="The right-middle catches late and helps throw the climax back across the stage.",
                    motion="crescendo-rebound",
                    peak_level=0.96,
                    points=[(0.00, 0.0), (0.24, 0.04), (0.42, 0.24), (0.64, 0.60), (0.80, 0.90), (0.92, 0.96), (0.98, 0.16), (1.00, 0.0)],
                ),
                "alto_l1": PartPlan(
                    summary="The far-right edge peaks last, completing the full-range sweep into the next trigger.",
                    motion="crescendo-rebound",
                    peak_level=0.98,
                    points=[(0.00, 0.0), (0.30, 0.02), (0.50, 0.20), (0.70, 0.56), (0.86, 0.92), (0.96, 0.98), (1.00, 0.0)],
                ),
            },
        ),
        11: EventPlan(
            summary="The only fully unified gesture in the piece: all six staffs begin together in a slow glow ramp up and down, then split into staggered afterglow currents.",
            score_dynamics="f after ff crest",
            design_tags=["unified_slow_glow", "only_unison_torch_moment", "afterglow_split"],
            duration_scale=0.95,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan(
                    summary="Shares the full-ensemble slow glow, then releases first into a soft left-edge shimmer.",
                    motion="unified-then-left-release",
                    peak_level=0.92,
                    points=[(0.00, 0.0), (0.18, 0.42), (0.34, 0.92), (0.50, 0.18), (0.64, 0.34), (0.78, 0.22), (0.92, 0.08), (1.00, 0.0)],
                ),
                "soprano_l2": PartPlan(
                    summary="After the shared glow, soprano L2 keeps a hovering upper-left remnant.",
                    motion="unified-then-hover",
                    peak_level=0.92,
                    points=[(0.00, 0.0), (0.18, 0.42), (0.34, 0.92), (0.50, 0.18), (0.68, 0.38), (0.82, 0.24), (0.94, 0.08), (1.00, 0.0)],
                ),
                "tenor_l": PartPlan(
                    summary="Tenor holds the center after the unified crest, acting as the pivot of the split.",
                    motion="unified-then-center-pivot",
                    peak_level=0.92,
                    points=[(0.00, 0.0), (0.18, 0.42), (0.34, 0.92), (0.50, 0.18), (0.66, 0.44), (0.82, 0.26), (0.95, 0.08), (1.00, 0.0)],
                ),
                "bass_l": PartPlan(
                    summary="Bass sustains the richest central afterglow once the unison has broken apart.",
                    motion="unified-then-center-pivot",
                    peak_level=0.92,
                    points=[(0.00, 0.0), (0.18, 0.42), (0.34, 0.92), (0.50, 0.18), (0.70, 0.40), (0.84, 0.24), (0.96, 0.08), (1.00, 0.0)],
                ),
                "alto_l2": PartPlan(
                    summary="After the shared ramp, alto L2 takes a delayed rightward shimmer.",
                    motion="unified-then-right-release",
                    peak_level=0.92,
                    points=[(0.00, 0.0), (0.18, 0.42), (0.34, 0.92), (0.50, 0.18), (0.74, 0.34), (0.88, 0.20), (0.98, 0.06), (1.00, 0.0)],
                ),
                "alto_l1": PartPlan(
                    summary="The far-right edge breaks away last, completing the afterglow split.",
                    motion="unified-then-right-release",
                    peak_level=0.92,
                    points=[(0.00, 0.0), (0.18, 0.42), (0.34, 0.92), (0.50, 0.18), (0.78, 0.32), (0.90, 0.18), (0.99, 0.04), (1.00, 0.0)],
                ),
            },
        ),
        12: EventPlan(
            summary="From measure 115 onward, every light entrance is locked to actual light-chorus note onsets, dissolving only through score-synchronous rhythmic residue.",
            score_dynamics="p / pp final release",
            design_tags=["finale", "note_synchronous", "rhythmic_lock", "dissolve"],
            duration_scale=None,
            fixed_duration_ms=TP12_FIXED_DURATION_MS,
            parts=_build_tp12_parts(),
        ),
    }


def _build_lighting_manifest() -> dict[str, Any]:
    trigger_manifest = json.loads(TRIGGER_MANIFEST_PATH.read_text())
    events = trigger_manifest["events"]
    source_duration_ms = float(trigger_manifest["sourceDurationMs"])
    event_plans = _build_event_plans()

    result_events: list[dict[str, Any]] = []
    for index, event in enumerate(events):
        event_id = int(event["id"])
        plan = event_plans[event_id]
        onset_ms = float(event["onsetMilliseconds"])
        if index < len(events) - 1:
            next_onset_ms = float(events[index + 1]["onsetMilliseconds"])
            available_window_ms = next_onset_ms - onset_ms
        else:
            available_window_ms = source_duration_ms - onset_ms

        duration_ms = _resolve_event_duration_ms(event_id, available_window_ms, plan)
        parts_payload: dict[str, Any] = {}
        for part_key in PART_ORDER:
            part_plan = plan.parts[part_key]
            keyframes = _scale_points(duration_ms, part_plan.points)
            parts_payload[part_key] = {
                "label": PART_LABELS[part_key],
                "summary": part_plan.summary,
                "motion": part_plan.motion,
                "peakLevel": round(part_plan.peak_level, 3),
                "durationMs": round(duration_ms, 3),
                "keyframes": keyframes,
            }

        result_events.append(
            {
                "id": event_id,
                "measure": event.get("measure"),
                "position": event.get("position"),
                "scoreLabel": event.get("scoreLabel"),
                "summary": plan.summary,
                "scoreDynamics": plan.score_dynamics,
                "designTags": plan.design_tags,
                "availableWindowMs": round(available_window_ms, 3),
                "durationMs": round(duration_ms, 3),
                "parts": parts_payload,
            }
        )

    return {
        "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "sourceMusicXml": str(MUSICXML_PATH.relative_to(REPO_ROOT)),
        "sourceTriggerManifest": str(TRIGGER_MANIFEST_PATH.relative_to(REPO_ROOT)),
        "stageOrder": [
            {"key": key, "label": PART_LABELS[key]}
            for key in PART_ORDER
        ],
        "events": result_events,
    }


def _inject_lighting_into_recipes(light_manifest: dict[str, Any]) -> None:
    events_by_id = {event["id"]: event for event in light_manifest["events"]}
    generated = light_manifest["generated"]

    for path in RECIPE_COPY_PATHS:
        bundle = json.loads(path.read_text())
        bundle["lightingSourceMusicXml"] = light_manifest["sourceMusicXml"]
        bundle["lightingManifest"] = str(LIGHT_SHOW_MANIFEST_PATH.relative_to(REPO_ROOT))
        bundle["lightingGenerated"] = generated
        bundle["lightingDesignNote"] = (
            "Twelve trigger-point torch choreography authored for the six-staff light chorus. "
            "Trigger Point 11 begins with the piece's only fully unified slow glow ramp before splitting apart again."
        )

        for event in bundle.get("events", []):
            event_id = int(event["id"])
            lighting = events_by_id[event_id]
            event["lighting"] = {
                "summary": lighting["summary"],
                "scoreDynamics": lighting["scoreDynamics"],
                "designTags": lighting["designTags"],
                "durationMs": lighting["durationMs"],
                "parts": deepcopy(lighting["parts"]),
            }

        path.write_text(json.dumps(bundle, indent=2) + "\n")


def main() -> None:
    light_manifest = _build_lighting_manifest()
    LIGHT_SHOW_MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    LIGHT_SHOW_MANIFEST_PATH.write_text(json.dumps(light_manifest, indent=2) + "\n")
    _inject_lighting_into_recipes(light_manifest)

    print(f"Light-show manifest: {LIGHT_SHOW_MANIFEST_PATH.relative_to(REPO_ROOT)}")
    print(f"Recipe copies updated: {len(RECIPE_COPY_PATHS)}")


if __name__ == "__main__":
    main()
