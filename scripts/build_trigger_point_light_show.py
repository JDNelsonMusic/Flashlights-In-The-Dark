#!/usr/bin/env python3
"""Build the tour-cut flashlight choreography for the reduced trigger workflow."""

from __future__ import annotations

import json
import re
import xml.etree.ElementTree as ET
from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
TRIGGER_MANIFEST_PATH = REPO_ROOT / "docs/protools-housekeeping/electronics_trigger_assets.json"
MUSICXML_PATH = REPO_ROOT / "flashlights_client/assets/FlashlightsInTheDark_v32_TourCut.musicxml"
LIGHT_SHOW_MANIFEST_PATH = REPO_ROOT / "docs/score-study/tour_cut_light_show.json"

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

FINAL_VOICE_MAP = {
    "soprano_l1": ("P4", "1"),
    "soprano_l2": ("P4", "2"),
    "alto_l1": ("P5", "1"),
    "alto_l2": ("P5", "2"),
    "tenor_l": ("P6", "1"),
    "bass_l": ("P6", "2"),
}

FINAL_BASE_LEVELS = {
    "soprano_l1": 0.24,
    "soprano_l2": 0.26,
    "tenor_l": 0.30,
    "bass_l": 0.34,
    "alto_l2": 0.22,
    "alto_l1": 0.20,
}


@dataclass(frozen=True)
class PartPlan:
    summary: str
    motion: str
    peak_level: float
    points: list[tuple[float, float] | tuple[float, float, str]]


@dataclass(frozen=True)
class EventPlan:
    summary: str
    score_dynamics: str
    design_tags: list[str]
    duration_scale: float | None
    fixed_duration_ms: float | None
    parts: dict[str, PartPlan] | None


def _scale_points(
    duration_ms: float,
    points: list[tuple[float, float] | tuple[float, float, str]],
) -> list[dict[str, float | str]]:
    keyframes: list[dict[str, float | str]] = []
    for raw_point in points:
        fraction = raw_point[0]
        level = raw_point[1]
        interpolation = raw_point[2] if len(raw_point) > 2 else "linear"
        entry: dict[str, float | str] = {
            "atMs": round(duration_ms * fraction, 3),
            "level": round(max(0.0, min(level, 1.0)), 3),
        }
        if interpolation != "linear":
            entry["interpolation"] = interpolation
        keyframes.append(entry)

    if not keyframes:
        return [{"atMs": 0.0, "level": 0.0}]
    if keyframes[0]["atMs"] != 0.0:
        keyframes.insert(0, {"atMs": 0.0, "level": 0.0})
    if keyframes[-1]["atMs"] != round(duration_ms, 3):
        keyframes.append({"atMs": round(duration_ms, 3), "level": 0.0})
    else:
        keyframes[-1]["level"] = 0.0
    return keyframes


def _dedupe_fraction_points(
    points: list[tuple[float, float] | tuple[float, float, str]],
) -> list[tuple[float, float] | tuple[float, float, str]]:
    deduped: dict[float, tuple[float, float] | tuple[float, float, str]] = {}
    for point in sorted(points, key=lambda item: item[0]):
        key = round(point[0], 6)
        existing = deduped.get(key)
        if existing is None or point[1] >= existing[1]:
            deduped[key] = point
    return [deduped[key] for key in sorted(deduped)]


def _measure_base_number(raw: str | None) -> int | None:
    if raw is None:
        return None
    match = re.match(r"^(\d+)", raw.strip())
    if match is None:
        return None
    return int(match.group(1))


def _collect_final_voice_onsets() -> dict[str, list[dict[str, float | bool]]]:
    root = ET.parse(MUSICXML_PATH).getroot()
    parts = {part.attrib["id"]: part for part in root.findall("part")}
    result: dict[str, list[dict[str, float | bool]]] = {}

    for part_key, (part_id, target_voice) in FINAL_VOICE_MAP.items():
        part = parts[part_id]
        current_divisions = 1
        beats_since_115 = 0.0
        captured: list[dict[str, float | bool]] = []

        for measure in part.findall("measure"):
            base_measure = _measure_base_number(measure.attrib.get("number"))
            attrs = measure.find("attributes")
            if attrs is not None and attrs.findtext("divisions"):
                current_divisions = int(attrs.findtext("divisions"))

            if base_measure is None or base_measure < 115:
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
                    captured.append(
                        {
                            "onsetBeats": beats_since_115 + (onset_divisions / current_divisions),
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


def _build_final_parts(duration_ms: float) -> dict[str, PartPlan]:
    onset_map = _collect_final_voice_onsets()
    ms_per_beat = 60000.0 / 72.0
    parts: dict[str, PartPlan] = {}

    for part_key in PART_ORDER:
        records = onset_map[part_key]
        points: list[tuple[float, float] | tuple[float, float, str]] = [(0.0, 0.0, "step")]
        for index, record in enumerate(records):
            onset_ms = float(record["onsetBeats"]) * ms_per_beat
            next_onset_ms = (
                float(records[index + 1]["onsetBeats"]) * ms_per_beat
                if index + 1 < len(records)
                else duration_ms
            )
            gap_ms = max(150.0, next_onset_ms - onset_ms)
            peak = min(
                FINAL_BASE_LEVELS[part_key] + (0.05 if bool(record["measureDownbeat"]) else 0.0),
                0.40,
            )
            pulse_ms = min(200.0 if bool(record["measureDownbeat"]) else 120.0, gap_ms * 0.45)
            off_ms = min(duration_ms, onset_ms + pulse_ms)
            points.append((onset_ms / duration_ms, peak, "step"))
            points.append((off_ms / duration_ms, 0.0, "step"))

        normalised = _dedupe_fraction_points(points)
        parts[part_key] = PartPlan(
            summary=(
                "Every flash is locked to actual note onsets from measure 115 onward, "
                "with no interpolated swell between attacks."
            ),
            motion="note-synchronous",
            peak_level=round(max(point[1] for point in normalised), 3),
            points=normalised,
        )

    return parts


def _resolve_event_duration_ms(available_window_ms: float, plan: EventPlan) -> float:
    if plan.fixed_duration_ms is not None:
        return plan.fixed_duration_ms
    scale = plan.duration_scale if plan.duration_scale is not None else 0.92
    return round(available_window_ms * scale, 3)


def _build_event_plans() -> dict[int, EventPlan]:
    return {
        1: EventPlan(
            summary="Darkness opens from stage left and only gradually reaches the far-right edge.",
            score_dynamics="ppp -> p",
            design_tags=["opening", "left_to_right", "emergence"],
            duration_scale=0.96,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan("Leads the first glint at the far-left edge.", "lead-left", 0.18, [(0.00, 0.0), (0.14, 0.18), (0.42, 0.08), (0.78, 0.02), (1.00, 0.0)]),
                "soprano_l2": PartPlan("Answers just right of the opening spark.", "left-to-right", 0.16, [(0.00, 0.0), (0.22, 0.03), (0.42, 0.16), (0.62, 0.06), (1.00, 0.0)]),
                "tenor_l": PartPlan("A low ember wakes after the sopranos.", "center-late", 0.14, [(0.00, 0.0), (0.34, 0.02), (0.56, 0.14), (0.74, 0.05), (1.00, 0.0)]),
                "bass_l": PartPlan("Bass arrives last, kept deliberately restrained.", "center-late", 0.12, [(0.00, 0.0), (0.42, 0.01), (0.64, 0.12), (0.82, 0.04), (1.00, 0.0)]),
                "alto_l2": PartPlan("A small right-side shimmer catches only near the end.", "tail-answer", 0.08, [(0.00, 0.0), (0.60, 0.0), (0.80, 0.08), (0.92, 0.03), (1.00, 0.0)]),
                "alto_l1": PartPlan("The far-right edge barely speaks before Trigger 2.", "tail-answer", 0.06, [(0.00, 0.0), (0.72, 0.0), (0.88, 0.06), (1.00, 0.0)]),
            },
        ),
        2: EventPlan(
            summary="Measures 11–19 become a field of hard max-brightness glitter, thrown in fast irregular cuts across the ensemble.",
            score_dynamics="f",
            design_tags=["binary_glitter", "stochastic", "cross_stage", "mm11_19"],
            duration_scale=0.95,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan("Upper-left flashes initiate the glitter swarm.", "binary-glitter", 1.0, [(0.00, 0.0), (0.14, 0.86), (0.30, 0.14), (0.38, 0.0), (0.400, 1.0, "step"), (0.414, 0.0, "step"), (0.452, 1.0, "step"), (0.466, 0.0, "step"), (0.514, 1.0, "step"), (0.528, 0.0, "step"), (0.580, 1.0, "step"), (0.594, 0.0, "step"), (0.658, 1.0, "step"), (0.672, 0.0), (0.80, 0.66), (1.00, 0.0)]),
                "soprano_l2": PartPlan("Sop-L2 interlocks with Sop-L1 in upper-left hard glitter.", "binary-glitter", 1.0, [(0.00, 0.0), (0.18, 0.82), (0.34, 0.18), (0.39, 0.0), (0.422, 1.0, "step"), (0.436, 0.0, "step"), (0.484, 1.0, "step"), (0.498, 0.0, "step"), (0.546, 1.0, "step"), (0.560, 0.0, "step"), (0.620, 1.0, "step"), (0.634, 0.0, "step"), (0.706, 1.0, "step"), (0.720, 0.0), (0.84, 0.58), (1.00, 0.0)]),
                "tenor_l": PartPlan("The middle-left becomes a restless engine of full-power irregular cuts.", "binary-glitter", 1.0, [(0.00, 0.0), (0.22, 0.76), (0.36, 0.16), (0.394, 1.0, "step"), (0.408, 0.0, "step"), (0.446, 1.0, "step"), (0.460, 0.0, "step"), (0.506, 1.0, "step"), (0.520, 0.0, "step"), (0.570, 1.0, "step"), (0.584, 0.0, "step"), (0.648, 1.0, "step"), (0.662, 0.0, "step"), (0.734, 1.0, "step"), (0.748, 0.0), (0.86, 0.52), (1.00, 0.0)]),
                "bass_l": PartPlan("Bass anchors the glitter with the deepest max-brightness strikes.", "binary-glitter", 1.0, [(0.00, 0.0), (0.26, 0.72), (0.37, 0.0), (0.410, 1.0, "step"), (0.424, 0.0, "step"), (0.470, 1.0, "step"), (0.484, 0.0, "step"), (0.534, 1.0, "step"), (0.548, 0.0, "step"), (0.606, 1.0, "step"), (0.620, 0.0, "step"), (0.684, 1.0, "step"), (0.698, 0.0), (0.84, 0.50), (1.00, 0.0)]),
                "alto_l2": PartPlan("Right-middle replies arrive as bright, clipped sparks.", "binary-glitter", 1.0, [(0.00, 0.0), (0.30, 0.78), (0.38, 0.0), (0.430, 1.0, "step"), (0.444, 0.0, "step"), (0.494, 1.0, "step"), (0.508, 0.0, "step"), (0.560, 1.0, "step"), (0.574, 0.0, "step"), (0.632, 1.0, "step"), (0.646, 0.0, "step"), (0.716, 1.0, "step"), (0.730, 0.0), (0.86, 0.56), (1.00, 0.0)]),
                "alto_l1": PartPlan("The far-right edge throws back the latest and brightest hard sparks.", "binary-glitter", 1.0, [(0.00, 0.0), (0.34, 0.84), (0.40, 0.0), (0.454, 1.0, "step"), (0.468, 0.0, "step"), (0.520, 1.0, "step"), (0.534, 0.0, "step"), (0.590, 1.0, "step"), (0.604, 0.0, "step"), (0.670, 1.0, "step"), (0.684, 0.0), (0.82, 0.70), (1.00, 0.0)]),
            },
        ),
        3: EventPlan(
            summary="The glare breaks into a soft right-to-left retreat with long afterimages.",
            score_dynamics="p",
            design_tags=["afterimage", "right_to_left", "decrescendo"],
            duration_scale=0.93,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan("Receives only the last remnant of the retreat.", "receive", 0.22, [(0.00, 0.0), (0.54, 0.02), (0.72, 0.22), (0.88, 0.06), (1.00, 0.0)]),
                "soprano_l2": PartPlan("Lights after the altos, then falls back into dark.", "receive", 0.24, [(0.00, 0.0), (0.38, 0.03), (0.58, 0.24), (0.78, 0.08), (1.00, 0.0)]),
                "tenor_l": PartPlan("Carries the center of the decrescendo for the longest span.", "center-carry", 0.28, [(0.00, 0.0), (0.26, 0.05), (0.46, 0.28), (0.64, 0.14), (0.84, 0.04), (1.00, 0.0)]),
                "bass_l": PartPlan("A grounded low glow lingers under the receding wave.", "low-anchor", 0.26, [(0.00, 0.0), (0.18, 0.04), (0.38, 0.26), (0.58, 0.16), (0.80, 0.05), (1.00, 0.0)]),
                "alto_l2": PartPlan("Starts the retreat with a soft but clear right-side lead.", "lead-right", 0.30, [(0.00, 0.0), (0.08, 0.08), (0.24, 0.30), (0.48, 0.12), (0.72, 0.04), (1.00, 0.0)]),
                "alto_l1": PartPlan("The far-right edge speaks first, then withdraws fastest.", "lead-right", 0.34, [(0.00, 0.0), (0.04, 0.10), (0.20, 0.34), (0.38, 0.10), (0.60, 0.02), (1.00, 0.0)]),
            },
        ),
        4: EventPlan(
            summary="A compact pulse ignites from the middle and flicks outward in one compressed gesture.",
            score_dynamics="p -> mp",
            design_tags=["center_out", "compressed_pulse"],
            duration_scale=0.90,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan("Catches the outermost left splash at the end.", "outer-splash", 0.26, [(0.00, 0.0), (0.60, 0.02), (0.78, 0.26), (0.92, 0.06), (1.00, 0.0)]),
                "soprano_l2": PartPlan("Supports the left-hand rebound after the central burst.", "outer-splash", 0.30, [(0.00, 0.0), (0.44, 0.04), (0.64, 0.30), (0.82, 0.10), (1.00, 0.0)]),
                "tenor_l": PartPlan("The first clear ignition appears in the center-left.", "center-ignite", 0.40, [(0.00, 0.0), (0.12, 0.10), (0.30, 0.40), (0.52, 0.18), (0.76, 0.04), (1.00, 0.0)]),
                "bass_l": PartPlan("Bass answers the central pulse with a short low bloom.", "center-ignite", 0.36, [(0.00, 0.0), (0.10, 0.08), (0.28, 0.36), (0.48, 0.16), (0.74, 0.04), (1.00, 0.0)]),
                "alto_l2": PartPlan("The right-middle receives the pulse after the center.", "outer-splash", 0.28, [(0.00, 0.0), (0.34, 0.04), (0.56, 0.28), (0.76, 0.09), (1.00, 0.0)]),
                "alto_l1": PartPlan("The far-right edge takes the final flick outward.", "outer-splash", 0.24, [(0.00, 0.0), (0.54, 0.03), (0.74, 0.24), (0.90, 0.06), (1.00, 0.0)]),
            },
        ),
        5: EventPlan(
            summary="The ensemble narrows into a held threshold, preparing the cut-bridge.",
            score_dynamics="mp -> p",
            design_tags=["threshold", "narrowing", "pre_bridge"],
            duration_scale=0.94,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan("Holds a narrow left edge of light.", "narrow-hold", 0.24, [(0.00, 0.0), (0.14, 0.18), (0.46, 0.24), (0.80, 0.12), (1.00, 0.0)]),
                "soprano_l2": PartPlan("Keeps the left-center suspended just under the sopranos.", "narrow-hold", 0.22, [(0.00, 0.0), (0.16, 0.16), (0.48, 0.22), (0.82, 0.10), (1.00, 0.0)]),
                "tenor_l": PartPlan("Acts as the center seam of the threshold.", "center-seam", 0.20, [(0.00, 0.0), (0.18, 0.12), (0.50, 0.20), (0.82, 0.08), (1.00, 0.0)]),
                "bass_l": PartPlan("Bass stays dim and grounded, barely moving.", "center-seam", 0.18, [(0.00, 0.0), (0.20, 0.10), (0.54, 0.18), (0.84, 0.07), (1.00, 0.0)]),
                "alto_l2": PartPlan("Right-middle remains present but subdued.", "narrow-hold", 0.18, [(0.00, 0.0), (0.22, 0.08), (0.54, 0.18), (0.84, 0.08), (1.00, 0.0)]),
                "alto_l1": PartPlan("The far-right edge becomes the faintest active contour.", "narrow-hold", 0.16, [(0.00, 0.0), (0.24, 0.06), (0.58, 0.16), (0.86, 0.08), (1.00, 0.0)]),
            },
        ),
        6: EventPlan(
            summary="The first rest-measure bridge begins as isolated twinkles, mostly left and center, with all flashes either fully on or dark.",
            score_dynamics="p / scattered",
            design_tags=["bridge", "binary_twinkle", "left_bias"],
            duration_scale=0.98,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan("Leftmost twinkles start the bridge.", "binary-twinkle", 1.0, [(0.00, 0.0), (0.10, 1.0, "step"), (0.16, 0.0, "step"), (0.34, 1.0, "step"), (0.40, 0.0, "step"), (0.68, 1.0, "step"), (0.74, 0.0), (1.00, 0.0)]),
                "soprano_l2": PartPlan("Sop-L2 answers with slightly delayed sparkles.", "binary-twinkle", 1.0, [(0.00, 0.0), (0.18, 1.0, "step"), (0.24, 0.0, "step"), (0.48, 1.0, "step"), (0.54, 0.0, "step"), (0.82, 1.0, "step"), (0.88, 0.0), (1.00, 0.0)]),
                "tenor_l": PartPlan("Center-left flickers between the soprano attacks.", "binary-twinkle", 1.0, [(0.00, 0.0), (0.26, 1.0, "step"), (0.32, 0.0, "step"), (0.58, 1.0, "step"), (0.64, 0.0), (1.00, 0.0)]),
                "bass_l": PartPlan("Bass stays mostly dark with two deep punctures.", "binary-twinkle", 1.0, [(0.00, 0.0), (0.42, 1.0, "step"), (0.48, 0.0, "step"), (0.74, 1.0, "step"), (0.80, 0.0), (1.00, 0.0)]),
                "alto_l2": PartPlan("Right-middle glints only late in the measure.", "binary-twinkle", 1.0, [(0.00, 0.0), (0.56, 1.0, "step"), (0.62, 0.0, "step"), (0.88, 1.0, "step"), (0.94, 0.0), (1.00, 0.0)]),
                "alto_l1": PartPlan("The far-right edge stays nearly absent.", "binary-twinkle", 1.0, [(0.00, 0.0), (0.72, 1.0, "step"), (0.78, 0.0), (1.00, 0.0)]),
            },
        ),
        7: EventPlan(
            summary="The bridge spark-field expands across all six staves in quick stochastic binary glitter.",
            score_dynamics="mp",
            design_tags=["bridge", "binary_glitter", "full_ensemble"],
            duration_scale=0.98,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan("Fast left-edge glitter opens the expanded bridge.", "binary-glitter", 1.0, [(0.00, 0.0), (0.08, 1.0, "step"), (0.13, 0.0, "step"), (0.28, 1.0, "step"), (0.33, 0.0, "step"), (0.52, 1.0, "step"), (0.57, 0.0, "step"), (0.78, 1.0, "step"), (0.83, 0.0), (1.00, 0.0)]),
                "soprano_l2": PartPlan("Upper-left replies tighten the density.", "binary-glitter", 1.0, [(0.00, 0.0), (0.14, 1.0, "step"), (0.19, 0.0, "step"), (0.34, 1.0, "step"), (0.39, 0.0, "step"), (0.60, 1.0, "step"), (0.65, 0.0, "step"), (0.86, 1.0, "step"), (0.91, 0.0), (1.00, 0.0)]),
                "tenor_l": PartPlan("Tenor drives the center of the stochastic mesh.", "binary-glitter", 1.0, [(0.00, 0.0), (0.10, 1.0, "step"), (0.15, 0.0, "step"), (0.26, 1.0, "step"), (0.31, 0.0, "step"), (0.48, 1.0, "step"), (0.53, 0.0, "step"), (0.70, 1.0, "step"), (0.75, 0.0), (1.00, 0.0)]),
                "bass_l": PartPlan("Bass reinforces the center with slower heavy cuts.", "binary-glitter", 1.0, [(0.00, 0.0), (0.20, 1.0, "step"), (0.26, 0.0, "step"), (0.46, 1.0, "step"), (0.52, 0.0, "step"), (0.74, 1.0, "step"), (0.80, 0.0), (1.00, 0.0)]),
                "alto_l2": PartPlan("Right-middle joins the texture in staggered cuts.", "binary-glitter", 1.0, [(0.00, 0.0), (0.24, 1.0, "step"), (0.29, 0.0, "step"), (0.44, 1.0, "step"), (0.49, 0.0, "step"), (0.66, 1.0, "step"), (0.71, 0.0), (1.00, 0.0)]),
                "alto_l1": PartPlan("The far-right edge punctures the field with fewer, brighter cuts.", "binary-glitter", 1.0, [(0.00, 0.0), (0.36, 1.0, "step"), (0.41, 0.0, "step"), (0.62, 1.0, "step"), (0.67, 0.0, "step"), (0.88, 1.0, "step"), (0.93, 0.0), (1.00, 0.0)]),
            },
        ),
        8: EventPlan(
            summary="A denser bridge crest sweeps right-to-left, still strictly max-brightness or off.",
            score_dynamics="mf",
            design_tags=["bridge", "binary_glitter", "right_to_left"],
            duration_scale=0.98,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan("Receives the returning sweep last, after the center has already flashed.", "binary-sweep", 1.0, [(0.00, 0.0), (0.46, 1.0, "step"), (0.51, 0.0, "step"), (0.74, 1.0, "step"), (0.79, 0.0), (1.00, 0.0)]),
                "soprano_l2": PartPlan("Upper-left joins late in the return sweep.", "binary-sweep", 1.0, [(0.00, 0.0), (0.36, 1.0, "step"), (0.41, 0.0, "step"), (0.64, 1.0, "step"), (0.69, 0.0), (1.00, 0.0)]),
                "tenor_l": PartPlan("Tenor catches the wave after the altos but before the sopranos.", "binary-sweep", 1.0, [(0.00, 0.0), (0.28, 1.0, "step"), (0.33, 0.0, "step"), (0.56, 1.0, "step"), (0.61, 0.0, "step"), (0.82, 1.0, "step"), (0.87, 0.0), (1.00, 0.0)]),
                "bass_l": PartPlan("Bass carries the heaviest middle-stage cuts.", "binary-sweep", 1.0, [(0.00, 0.0), (0.22, 1.0, "step"), (0.28, 0.0, "step"), (0.46, 1.0, "step"), (0.52, 0.0, "step"), (0.70, 1.0, "step"), (0.76, 0.0), (1.00, 0.0)]),
                "alto_l2": PartPlan("Right-middle launches the sweep with repeated bright cuts.", "binary-sweep", 1.0, [(0.00, 0.0), (0.08, 1.0, "step"), (0.14, 0.0, "step"), (0.30, 1.0, "step"), (0.36, 0.0, "step"), (0.58, 1.0, "step"), (0.64, 0.0), (1.00, 0.0)]),
                "alto_l1": PartPlan("The far-right edge begins the crest in the starkest cuts.", "binary-sweep", 1.0, [(0.00, 0.0), (0.04, 1.0, "step"), (0.10, 0.0, "step"), (0.24, 1.0, "step"), (0.30, 0.0, "step"), (0.48, 1.0, "step"), (0.54, 0.0), (1.00, 0.0)]),
            },
        ),
        9: EventPlan(
            summary="The final bridge measure gathers the sparkle inward and leaves a dark breath before the return.",
            score_dynamics="mf -> pp",
            design_tags=["bridge", "gathering", "pre_reentry"],
            duration_scale=0.99,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan("Only two late left-edge sparks survive the gathering.", "binary-gather", 1.0, [(0.00, 0.0), (0.30, 1.0, "step"), (0.36, 0.0, "step"), (0.66, 1.0, "step"), (0.72, 0.0), (1.00, 0.0)]),
                "soprano_l2": PartPlan("Sop-L2 narrows toward the center and then vanishes.", "binary-gather", 1.0, [(0.00, 0.0), (0.22, 1.0, "step"), (0.28, 0.0, "step"), (0.54, 1.0, "step"), (0.60, 0.0), (1.00, 0.0)]),
                "tenor_l": PartPlan("Tenor becomes the central meeting point of the bridge.", "binary-gather", 1.0, [(0.00, 0.0), (0.16, 1.0, "step"), (0.22, 0.0, "step"), (0.40, 1.0, "step"), (0.46, 0.0, "step"), (0.74, 1.0, "step"), (0.80, 0.0), (1.00, 0.0)]),
                "bass_l": PartPlan("Bass gives the last low-center flash before darkness.", "binary-gather", 1.0, [(0.00, 0.0), (0.26, 1.0, "step"), (0.32, 0.0, "step"), (0.62, 1.0, "step"), (0.68, 0.0), (1.00, 0.0)]),
                "alto_l2": PartPlan("Right-middle flashes early, then cedes the space.", "binary-gather", 1.0, [(0.00, 0.0), (0.10, 1.0, "step"), (0.16, 0.0, "step"), (0.38, 1.0, "step"), (0.44, 0.0), (1.00, 0.0)]),
                "alto_l1": PartPlan("The far-right edge withdraws first to clear the reentry.", "binary-gather", 1.0, [(0.00, 0.0), (0.06, 1.0, "step"), (0.12, 0.0, "step"), (0.28, 1.0, "step"), (0.34, 0.0), (1.00, 0.0)]),
            },
        ),
        10: EventPlan(
            summary="The chorus return begins with the piece’s only fully unified slow glow, then the six staves separate again.",
            score_dynamics="mp -> mf -> p",
            design_tags=["unified_glow", "reentry", "only_full_unison"],
            duration_scale=0.88,
            fixed_duration_ms=None,
            parts={
                "soprano_l1": PartPlan("Starts in perfect unison with the ensemble, then peels left.", "unified-then-split", 0.92, [(0.00, 0.0), (0.14, 0.40), (0.28, 0.92), (0.42, 0.18), (0.62, 0.30), (0.80, 0.12), (1.00, 0.0)]),
                "soprano_l2": PartPlan("Shares the same opening glow before separating slightly later.", "unified-then-split", 0.92, [(0.00, 0.0), (0.14, 0.40), (0.28, 0.92), (0.42, 0.18), (0.66, 0.32), (0.84, 0.14), (1.00, 0.0)]),
                "tenor_l": PartPlan("The center seam of the unified glow stays bright longest.", "unified-then-split", 0.92, [(0.00, 0.0), (0.14, 0.40), (0.28, 0.92), (0.46, 0.22), (0.70, 0.34), (0.86, 0.16), (1.00, 0.0)]),
                "bass_l": PartPlan("Bass anchors the common ramp and releases toward the floor.", "unified-then-split", 0.92, [(0.00, 0.0), (0.14, 0.40), (0.28, 0.92), (0.46, 0.20), (0.68, 0.30), (0.84, 0.14), (1.00, 0.0)]),
                "alto_l2": PartPlan("The right-center keeps the opening glow and then drifts outward.", "unified-then-split", 0.92, [(0.00, 0.0), (0.14, 0.40), (0.28, 0.92), (0.42, 0.18), (0.64, 0.30), (0.82, 0.14), (1.00, 0.0)]),
                "alto_l1": PartPlan("The far-right edge breaks away last, completing the split.", "unified-then-split", 0.92, [(0.00, 0.0), (0.14, 0.40), (0.28, 0.92), (0.42, 0.18), (0.68, 0.32), (0.86, 0.16), (1.00, 0.0)]),
            },
        ),
        11: EventPlan(
            summary="From measure 115 onward, every light entrance is locked to actual light-chorus note onsets and released only by silence.",
            score_dynamics="p / pp final release",
            design_tags=["finale", "note_synchronous", "rhythmic_lock", "tour_cut"],
            duration_scale=None,
            fixed_duration_ms=None,
            parts=None,
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
        design_event_id = 10 if event_id == 11 else (11 if event_id == 12 else event_id)
        plan = event_plans[design_event_id]
        onset_ms = float(event["onsetMilliseconds"])
        if index < len(events) - 1:
            next_onset_ms = float(events[index + 1]["onsetMilliseconds"])
            available_window_ms = next_onset_ms - onset_ms
        else:
            available_window_ms = source_duration_ms - onset_ms

        duration_ms = _resolve_event_duration_ms(available_window_ms, plan)
        parts_source = _build_final_parts(duration_ms) if event_id == 12 else plan.parts
        assert parts_source is not None

        parts_payload: dict[str, Any] = {}
        for part_key in PART_ORDER:
            part_plan = parts_source[part_key]
            parts_payload[part_key] = {
                "label": PART_LABELS[part_key],
                "summary": part_plan.summary,
                "motion": part_plan.motion,
                "peakLevel": round(part_plan.peak_level, 3),
                "durationMs": round(duration_ms, 3),
                "keyframes": _scale_points(duration_ms, part_plan.points),
            }

        result_events.append(
            {
                "id": event_id,
                "measure": event.get("measure"),
                "measureToken": event.get("measureToken"),
                "scoreMeasureOrdinal": event.get("scoreMeasureOrdinal"),
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
        "stageOrder": [{"key": key, "label": PART_LABELS[key]} for key in PART_ORDER],
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
            "Tour-cut six-staff torch choreography preserving full trigger identities 1, 2, 3, 4, 5, 8, 11, 12. "
            "Trigger Point 11 begins with the piece's only fully unified slow glow before the staves separate again; "
            "Trigger Point 12 is strictly locked to light-chorus note onsets."
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
