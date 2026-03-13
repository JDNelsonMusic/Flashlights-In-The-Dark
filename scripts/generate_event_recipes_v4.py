#!/usr/bin/env python3

from __future__ import annotations

import csv
import json
import re
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from fractions import Fraction
from pathlib import Path
import xml.etree.ElementTree as ET

try:
    from openpyxl import Workbook
    from openpyxl.styles import Font
except ImportError:  # pragma: no cover - optional export
    Workbook = None
    Font = None


ROOT = Path(__file__).resolve().parents[1]
OLD_BUNDLE_PATH = ROOT / "FlashlightsInTheDark_MacOS/Resources/event_recipes.json"
NEW_SCORE_PATH = (
    ROOT
    / "Flashlights-ITD_EventRecipes_4_2026_0309"
    / "FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml"
)
OUTPUT_DIR = ROOT / "Flashlights-ITD_EventRecipes_4_2026_0309"
OUTPUT_CSV_PATH = OUTPUT_DIR / "Flashlights-ITD_EventRecipes_4.csv"
OUTPUT_XLSX_PATH = OUTPUT_DIR / "Flashlights-ITD_EventRecipes_4.xlsx"
OUTPUT_JSON_PATH = OUTPUT_DIR / "event_recipes.json"
MAC_JSON_PATH = ROOT / "FlashlightsInTheDark_MacOS/Resources/event_recipes.json"
CLIENT_JSON_PATH = ROOT / "flashlights_client/assets/event_recipes.json"

POSITION_RE = re.compile(r"^(?P<beat>[\d+\/]+)-of-(?P<measure_beats>\d+)$")

STEP_TO_SEMITONE = {
    "C": 0,
    "D": 2,
    "E": 4,
    "F": 5,
    "G": 7,
    "A": 9,
    "B": 11,
}

ALTER_TO_ACCIDENTAL = {
    -2: "bb",
    -1: "b",
    0: "",
    1: "#",
    2: "##",
}

PART_TO_COLORS = {
    "P4": ["green", "magenta", "orange"],
    "P5": ["blue", "red", "cyan"],
    "P6": ["yellow", "pink", "purple"],
}

ROW_CONFIG = [
    ("green", "Sop L1", "Slots 16,29,44", "Green"),
    ("magenta", "Sop L2", "Slots 12,24,25", "Magenta"),
    ("orange", "Sop L2", "Slots 23,38,51", "Orange"),
    ("blue", "Alto L1", "Slots 27,41,42", "Blue"),
    ("red", "Alto L2", "Slots 1,14,15", "Red"),
    ("cyan", "Alto L2", "Slots 40,53,54", "Cyan"),
    ("yellow", "Tenor L1", "Slots 7,19,34", "Yellow"),
    ("pink", "Bass L1", "Slots 9,20,21", "Pink"),
    ("purple", "Bass L1", "Slots 3,4,18", "Purple"),
]


@dataclass(frozen=True)
class EventPoint:
    event_id: int
    measure: int
    position: str
    is_long: bool


@dataclass(frozen=True)
class MeasureContext:
    beats: int
    beat_type: int


@dataclass(frozen=True)
class NoteSpan:
    start: Fraction
    end: Fraction
    midi: int
    label: str


def load_legacy_event_points(path: Path) -> list[EventPoint]:
    bundle = json.loads(path.read_text())
    points: list[EventPoint] = []
    for event in bundle["events"]:
        primer = event.get("primer", {})
        samples = [assignment.get("sample", "") for assignment in primer.values()]
        is_long = any("long" in sample.lower() for sample in samples)
        points.append(
            EventPoint(
                event_id=event["id"],
                measure=event["measure"],
                position=event["position"],
                is_long=is_long,
            )
        )
    return points


def parse_mixed_number(raw: str) -> Fraction:
    raw = raw.strip()
    if "+" in raw:
        whole, fraction = raw.split("+", 1)
        return Fraction(int(whole)) + Fraction(fraction)
    return Fraction(raw)


def parse_position_offset(position: str, beat_type: int) -> Fraction:
    match = POSITION_RE.match(position.strip())
    if match is None:
        raise ValueError(f"Unsupported position format: {position}")
    beat_value = parse_mixed_number(match.group("beat"))
    return (beat_value - 1) * Fraction(4, beat_type)


def parse_pitch(note: ET.Element) -> tuple[int, str]:
    pitch = note.find("pitch")
    if pitch is None:
        raise ValueError("Expected pitch element")
    step = pitch.findtext("step")
    octave = pitch.findtext("octave")
    if step is None or octave is None:
        raise ValueError("Incomplete pitch data")
    alter = int(pitch.findtext("alter", "0"))
    octave_number = int(octave)
    midi = 12 * (octave_number + 1) + STEP_TO_SEMITONE[step] + alter
    accidental = ALTER_TO_ACCIDENTAL.get(alter, f"({alter})")
    return midi, f"{step}{accidental}{octave_number}"


def parse_part(part: ET.Element) -> tuple[dict[int, MeasureContext], dict[int, list[NoteSpan]]]:
    divisions = 1
    beats = 4
    beat_type = 4
    measure_contexts: dict[int, MeasureContext] = {}
    spans_by_measure: dict[int, list[NoteSpan]] = defaultdict(list)

    for measure in part.findall("measure"):
        raw_measure_number = measure.get("number", "")
        match = re.match(r"^(\d+)", raw_measure_number.strip())
        if match is None:
            continue
        measure_number = int(match.group(1))

        attributes = measure.find("attributes")
        if attributes is not None:
            divisions_text = attributes.findtext("divisions")
            if divisions_text:
                divisions = int(divisions_text)
            beats_text = attributes.findtext("time/beats")
            beat_type_text = attributes.findtext("time/beat-type")
            if beats_text and beat_type_text:
                beats = int(beats_text)
                beat_type = int(beat_type_text)

        measure_contexts[measure_number] = MeasureContext(
            beats=beats,
            beat_type=beat_type,
        )

        cursor = Fraction(0)
        last_note_start: Fraction | None = None
        for child in measure:
            if child.tag == "note":
                if child.find("grace") is not None:
                    continue
                duration_text = child.findtext("duration")
                duration = (
                    Fraction(int(duration_text), divisions)
                    if duration_text is not None
                    else Fraction(0)
                )
                is_chord = child.find("chord") is not None
                start = last_note_start if is_chord and last_note_start is not None else cursor

                if (
                    child.find("rest") is None
                    and child.get("print-object") != "no"
                    and duration > 0
                ):
                    midi, label = parse_pitch(child)
                    spans_by_measure[measure_number].append(
                        NoteSpan(start=start, end=start + duration, midi=midi, label=label)
                    )

                if not is_chord:
                    last_note_start = start
                    cursor += duration
            elif child.tag == "backup":
                duration_text = child.findtext("duration", "0")
                cursor -= Fraction(int(duration_text), divisions)
            elif child.tag == "forward":
                duration_text = child.findtext("duration", "0")
                cursor += Fraction(int(duration_text), divisions)

    return measure_contexts, spans_by_measure


def score_pitch_layers(
    spans_by_measure: dict[int, list[NoteSpan]],
    measure_contexts: dict[int, MeasureContext],
    measure: int,
    position: str,
) -> list[str]:
    context = measure_contexts.get(measure)
    if context is None:
        return []
    target = parse_position_offset(position, context.beat_type)
    active = [
        span
        for span in spans_by_measure.get(measure, [])
        if span.start <= target < span.end
    ]
    active.sort(key=lambda span: (span.midi, span.label), reverse=True)
    return [span.label for span in active]


def sample_name_for(note_label: str, *, is_long: bool) -> str:
    note_match = re.match(r"^([A-G])(bb|##|b|#)?(\d+)$", note_label)
    if note_match is None:
        raise ValueError(f"Unsupported note label: {note_label}")
    step = note_match.group(1)
    accidental = note_match.group(2) or ""
    octave = int(note_match.group(3))
    alter = {
        "bb": -2,
        "b": -1,
        "": 0,
        "#": 1,
        "##": 2,
    }[accidental]
    midi = 12 * (octave + 1) + STEP_TO_SEMITONE[step] + alter
    base_index = midi - 36
    if is_long:
        return f"primerTones/long{base_index + 50}.mp3"
    return f"primerTones/short{base_index}.mp3"


def expand_family_layers(pitches: list[str]) -> list[str]:
    if not pitches:
        return []
    if len(pitches) == 1:
        return [pitches[0], pitches[0], pitches[0]]
    if len(pitches) == 2:
        return [pitches[0], pitches[1], pitches[1]]
    return pitches[:3]


def build_bundle(
    event_points: list[EventPoint],
    score_data: dict[str, tuple[dict[int, MeasureContext], dict[int, list[NoteSpan]]]],
) -> dict[str, object]:
    events_payload: list[dict[str, object]] = []
    for event in event_points:
        primer: dict[str, dict[str, str]] = {}
        for part_id, colors in PART_TO_COLORS.items():
            measure_contexts, spans_by_measure = score_data[part_id]
            expanded = expand_family_layers(
                score_pitch_layers(
                    spans_by_measure=spans_by_measure,
                    measure_contexts=measure_contexts,
                    measure=event.measure,
                    position=event.position,
                )
            )
            for color, note_label in zip(colors, expanded):
                primer[color] = {
                    "sample": sample_name_for(note_label, is_long=event.is_long),
                    "note": note_label,
                }
        events_payload.append(
            {
                "id": event.event_id,
                "measure": event.measure,
                "position": event.position,
                "primer": primer,
            }
        )

    return {
        "source": str(NEW_SCORE_PATH.relative_to(ROOT)),
        "eventCount": len(events_payload),
        "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "events": events_payload,
    }


def build_spreadsheet_rows(bundle: dict[str, object]) -> list[list[str]]:
    events = bundle["events"]
    header_row = ["", "Event #"] + [str(event["id"]) for event in events]
    measure_row = ["", "Measure #"] + [str(event["measure"]) for event in events]
    position_row = ["", "Position (beat)"] + [str(event["position"]) for event in events]
    length_row = [
        "",
        "Sample Length",
        *[
            "LONG"
            if any(
                "long" in assignment["sample"].lower()
                for assignment in event.get("primer", {}).values()
            )
            else ""
            for event in events
        ],
    ]

    rows: list[list[str]] = [
        ["Source Score", str(NEW_SCORE_PATH.relative_to(ROOT))],
        [
            "Assignment Rule",
            "Legacy event timings with active light-chorus pitches sampled top-to-bottom per reduced staff; duplicate the lowest available layer when fewer than three pitches sound.",
        ],
        [],
        header_row,
        measure_row,
        position_row,
        length_row,
    ]

    for color, part_label, slots_label, display_color in ROW_CONFIG:
        sample_row = ["", f"{part_label}: {slots_label} [{display_color}]"]
        note_row = ["", f"CorrespondingNote {part_label} [{display_color}]"]
        for event in events:
            assignment = event.get("primer", {}).get(color)
            if assignment is None:
                sample_row.append("")
                note_row.append("")
            else:
                sample_row.append(assignment["sample"])
                note_row.append(assignment["note"])
        rows.append(sample_row)
        rows.append(note_row)

    rows.extend(
        [
            [],
            ["Mapping Reference", "Short0 = Long50 = C2"],
            ["Generated", str(bundle["generated"])],
        ]
    )
    return rows


def export_csv(rows: list[list[str]], path: Path) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerows(rows)


def export_xlsx(rows: list[list[str]], path: Path) -> None:
    if Workbook is None:
        return
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Event Recipes"

    for row_index, row in enumerate(rows, start=1):
        for column_index, value in enumerate(row, start=1):
            sheet.cell(row=row_index, column=column_index, value=value)

    for row_index in (4, 5, 6, 7):
        for cell in sheet[row_index]:
            cell.font = Font(bold=True)

    sheet.freeze_panes = "C4"
    workbook.save(path)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    event_points = load_legacy_event_points(OLD_BUNDLE_PATH)

    root = ET.parse(NEW_SCORE_PATH).getroot()
    score_data: dict[str, tuple[dict[int, MeasureContext], dict[int, list[NoteSpan]]]] = {}
    for part_id in PART_TO_COLORS:
        part = root.find(f".//part[@id='{part_id}']")
        if part is None:
            raise ValueError(f"Missing light-chorus part {part_id} in {NEW_SCORE_PATH}")
        score_data[part_id] = parse_part(part)

    bundle = build_bundle(event_points=event_points, score_data=score_data)
    rows = build_spreadsheet_rows(bundle)

    OUTPUT_JSON_PATH.write_text(json.dumps(bundle, indent=2) + "\n")
    MAC_JSON_PATH.write_text(json.dumps(bundle, indent=2) + "\n")
    CLIENT_JSON_PATH.write_text(json.dumps(bundle, indent=2) + "\n")
    export_csv(rows, OUTPUT_CSV_PATH)
    export_xlsx(rows, OUTPUT_XLSX_PATH)


if __name__ == "__main__":
    main()
