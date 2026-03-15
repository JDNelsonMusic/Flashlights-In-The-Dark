#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timezone
from fractions import Fraction
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_SCORE_PATH = (
    ROOT
    / "Flashlights-ITD_EventRecipes_4_2026_0309"
    / "FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml"
)
CUT_SCORE_SOURCE_PATH = (
    ROOT
    / "Flashlights-ITD_EventRecipes_4_2026_0309"
    / "FlashlightsInTheDark_v32_TourCut.musicxml"
)
CUT_SCORE_FLUTTER_PATH = (
    ROOT / "flashlights_client" / "assets" / "FlashlightsInTheDark_v32_TourCut.musicxml"
)
MANIFEST_PATH = ROOT / "docs" / "score-study" / "tour_cut_score_manifest.json"

BRIDGE_MEASURE_MAP = {
    38: "38",
    39: "38.2",
    40: "38.3",
    41: "38.4",
}
KEEP_UNTIL_MEASURE = 41
RESUME_AT_MEASURE = 104
MEASURE_NUMBER_RE = re.compile(r"^(\d+(?:\.\d+)?)$")


@dataclass
class MeasureState:
    divisions: int = 1
    beats: int = 4
    beat_type: int = 4


def iso_now() -> str:
    return datetime.now(tz=timezone.utc).isoformat(timespec="seconds")


def parse_measure_token(raw: str | None) -> str | None:
    if raw is None:
        return None
    token = raw.strip()
    if not token:
        return None
    if MEASURE_NUMBER_RE.match(token):
        return token
    match = re.match(r"^(\d+(?:\.\d+)?)", token)
    if match is None:
        return None
    return match.group(1)


def base_measure_number(token: str | None) -> int | None:
    if token is None:
        return None
    match = re.match(r"^(\d+)", token)
    if match is None:
        return None
    return int(match.group(1))


def update_state_from_measure(measure: ET.Element, state: MeasureState) -> None:
    attributes = measure.find("attributes")
    if attributes is None:
        return
    divisions_text = attributes.findtext("divisions")
    if divisions_text:
        state.divisions = int(divisions_text)
    beats_text = attributes.findtext("time/beats")
    beat_type_text = attributes.findtext("time/beat-type")
    if beats_text and beat_type_text:
        state.beats = int(beats_text)
        state.beat_type = int(beat_type_text)


def measure_duration_divisions(state: MeasureState) -> int:
    duration = Fraction(state.divisions * state.beats * 4, state.beat_type)
    if duration.denominator != 1:
        raise ValueError(
            f"Measure duration is not an integer division count: {state.divisions=} {state.beats=} {state.beat_type=}"
        )
    return int(duration)


def make_measure_rest(duration_divisions: int) -> ET.Element:
    note = ET.Element("note")
    rest = ET.SubElement(note, "rest")
    rest.set("measure", "yes")
    duration = ET.SubElement(note, "duration")
    duration.text = str(duration_divisions)
    voice = ET.SubElement(note, "voice")
    voice.text = "1"
    note_type = ET.SubElement(note, "type")
    note_type.text = "whole"
    staff = ET.SubElement(note, "staff")
    staff.text = "1"
    return note


def replace_with_rest_measure(measure: ET.Element, state: MeasureState) -> ET.Element:
    stripped = copy.deepcopy(measure)
    for child in list(stripped):
        if child.tag in {"note", "backup", "forward"}:
            stripped.remove(child)

    rest_note = make_measure_rest(measure_duration_divisions(state))
    insertion_index = len(stripped)
    for index, child in enumerate(list(stripped)):
        if child.tag == "barline":
            insertion_index = index
            break
    stripped.insert(insertion_index, rest_note)
    return stripped


def build_cut_score() -> tuple[ET.ElementTree, dict[str, object]]:
    tree = ET.parse(SOURCE_SCORE_PATH)
    root = tree.getroot()

    part_measure_manifest: dict[str, list[dict[str, object]]] = {}
    part_lists = root.findall("part")
    if not part_lists:
        raise ValueError(f"No parts found in {SOURCE_SCORE_PATH}")

    for part in part_lists:
        part_id = part.get("id", "")
        state = MeasureState()
        kept_measures: list[ET.Element] = []
        measure_rows: list[dict[str, object]] = []

        for measure in list(part.findall("measure")):
            token = parse_measure_token(measure.get("number"))
            base = base_measure_number(token)
            if token is None or base is None:
                continue

            update_state_from_measure(measure, state)

            if base < 38:
                new_measure = copy.deepcopy(measure)
                new_token = token
                source_role = "opening"
            elif base in BRIDGE_MEASURE_MAP:
                new_measure = replace_with_rest_measure(measure, state)
                new_token = BRIDGE_MEASURE_MAP[base]
                source_role = "tour_cut_rest_bridge"
            elif base >= RESUME_AT_MEASURE:
                new_measure = copy.deepcopy(measure)
                new_token = token
                source_role = "post_cut_survivor"
            else:
                continue

            new_measure.set("number", new_token)
            kept_measures.append(new_measure)
            measure_rows.append(
                {
                    "sourceMeasure": token,
                    "tourCutMeasure": new_token,
                    "baseMeasure": base,
                    "ordinal": len(measure_rows) + 1,
                    "role": source_role,
                }
            )

        for measure in list(part.findall("measure")):
            part.remove(measure)
        for measure in kept_measures:
            part.append(measure)

        part_measure_manifest[part_id] = measure_rows

    movement_title = root.find("movement-title")
    if movement_title is not None:
        movement_title.text = "Flashlights in the Dark (Tour Cut)"

    manifest = {
        "generated": iso_now(),
        "sourceScore": str(SOURCE_SCORE_PATH.relative_to(ROOT)),
        "cutScoreSource": str(CUT_SCORE_SOURCE_PATH.relative_to(ROOT)),
        "cutScoreFlutterAsset": str(CUT_SCORE_FLUTTER_PATH.relative_to(ROOT)),
        "bridgeMeasureLabels": list(BRIDGE_MEASURE_MAP.values()),
        "bridgeSourceMeasures": [str(number) for number in BRIDGE_MEASURE_MAP],
        "resumeAtMeasure": RESUME_AT_MEASURE,
        "parts": part_measure_manifest,
    }
    return tree, manifest


def write_outputs(tree: ET.ElementTree, manifest: dict[str, object]) -> None:
    CUT_SCORE_SOURCE_PATH.parent.mkdir(parents=True, exist_ok=True)
    CUT_SCORE_FLUTTER_PATH.parent.mkdir(parents=True, exist_ok=True)
    tree.write(CUT_SCORE_SOURCE_PATH, encoding="utf-8", xml_declaration=True)
    tree.write(CUT_SCORE_FLUTTER_PATH, encoding="utf-8", xml_declaration=True)
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n")


def main() -> None:
    if not SOURCE_SCORE_PATH.exists():
        raise FileNotFoundError(SOURCE_SCORE_PATH)
    tree, manifest = build_cut_score()
    write_outputs(tree, manifest)
    print(f"Wrote cut score: {CUT_SCORE_SOURCE_PATH.relative_to(ROOT)}")
    print(f"Wrote Flutter asset: {CUT_SCORE_FLUTTER_PATH.relative_to(ROOT)}")
    print(f"Manifest: {MANIFEST_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
