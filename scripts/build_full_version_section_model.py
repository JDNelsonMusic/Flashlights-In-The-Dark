#!/usr/bin/env python3
"""Add the 18-section visual form to the v26 full-version light-show schema.

The full-version performance keeps its twelve operator trigger points. This
builder derives eighteen internal visual sections from the v26 MusicXML and
records the portion of each section that falls inside every trigger window.
It deliberately does not modify the active Tour Cut runtime bundle.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from score_measure_utils import build_measure_token_map


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = ROOT / "docs/score-study/Flashlights_Lightshow_Prototype_Schema.json"
EXPECTED_MUSICXML = "flashlights_client/assets/FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml"


@dataclass(frozen=True)
class SectionPlan:
    section_id: int
    key: str
    label: str
    start_measure: int
    end_measure: int
    summary: str


SECTION_PLANS = [
    SectionPlan(1, "first_emergence", "First emergence", 1, 1, "Darkness releases the first left-to-right glint."),
    SectionPlan(2, "forte_shimmer", "Forte shimmer", 2, 9, "A bright shimmer accumulates toward the first ff crest."),
    SectionPlan(3, "niente_rupture", "Niente rupture", 10, 18, "Niente, reattack, and robot/rocket textures fracture the opening field."),
    SectionPlan(4, "clock_withdrawal", "Clock withdrawal", 19, 29, "The ensemble withdraws to mp and exposes the clock-ticking transition."),
    SectionPlan(5, "andante_reset", "Andante reset", 30, 35, "The new 72 BPM tempo opens a slower visual breathing space."),
    SectionPlan(6, "breathing_arc", "Breathing arc", 36, 45, "A moderate center-out breath expands across the six groups."),
    SectionPlan(7, "irregular_pendulum", "Irregular pendulum", 46, 56, "Changing meters suspend a pendulum between center and edges."),
    SectionPlan(8, "forte_expansion", "Forte expansion", 57, 64, "A renewed forte gesture expands and begins to release."),
    SectionPlan(9, "piano_rebuild", "Piano rebuild", 65, 70, "The texture thins to piano and gradually gathers weight again."),
    SectionPlan(10, "metered_forte_return", "Metered forte return", 71, 80, "Forte energy returns through a sequence of changing meters."),
    SectionPlan(11, "musique_concrete", "Musique concrete", 81, 88, "The musique-concrete region becomes its own visual environment."),
    SectionPlan(12, "isolated_lanterns", "Isolated lanterns", 89, 97, "Quiet asymmetric lanterns occupy separate pockets of the stage."),
    SectionPlan(13, "density_crescendo", "Density crescendo", 98, 103, "Binary glitter grows from p to ff through increasing density."),
    SectionPlan(14, "unified_glow", "Unified glow", 104, 111, "All six groups share the piece's only fully unified slow glow."),
    SectionPlan(15, "subito_contraction", "Subito contraction", 112, 114, "A subito mp contraction clears space for the final aleatoric field."),
    SectionPlan(16, "aleatoric_field_one", "Aleatoric field I", 115, 129, "The first note-synchronous aleatoric field follows individual entrances."),
    SectionPlan(17, "aleatoric_field_two", "Aleatoric field II", 130, 139, "Rearticulation produces a second, more dispersed onset field."),
    SectionPlan(18, "polytonal_chandelier", "Polytonal chandelier", 140, 151, "The polytonal chandelier dissolves into the final ppp release."),
]


def _position_offset_ms(position: str | None, measure: dict[str, Any]) -> float:
    match = re.fullmatch(r"beat\s*(\d+(?:\.\d+)?)", (position or "beat1").strip(), re.IGNORECASE)
    if match is None:
        raise ValueError(f"Unsupported score position: {position!r}")
    beat_number = float(match.group(1))
    seconds_per_beat = (60.0 / float(measure["tempo_bpm"])) * (4.0 / float(measure["beat_type"]))
    return max(0.0, beat_number - 1.0) * seconds_per_beat * 1000.0


def _event_onset_ms(event: dict[str, Any], measure_lookup: dict[str, dict[str, Any]]) -> float:
    token = str(event.get("measureToken") or event.get("measure"))
    measure = measure_lookup[token]
    return float(measure["start_seconds"]) * 1000.0 + _position_offset_ms(event.get("position"), measure)


def build_section_model(schema: dict[str, Any]) -> dict[str, Any]:
    if schema.get("sourceMusicXml") != EXPECTED_MUSICXML:
        raise ValueError(
            "The 18-section prototype must be built from v26; "
            f"found {schema.get('sourceMusicXml')!r}."
        )
    if len(schema.get("events", [])) != 12:
        raise ValueError("The full-version prototype must retain exactly 12 operator triggers.")

    _, measure_lookup, _ = build_measure_token_map(ROOT / EXPECTED_MUSICXML)
    events = schema["events"]
    event_onsets = [_event_onset_ms(event, measure_lookup) for event in events]
    source_duration_ms = event_onsets[-1] + float(events[-1]["availableWindowMs"])
    section_starts = [
        float(measure_lookup[str(plan.start_measure)]["start_seconds"]) * 1000.0
        for plan in SECTION_PLANS
    ]

    sections: list[dict[str, Any]] = []
    for index, plan in enumerate(SECTION_PLANS):
        start_ms = section_starts[index]
        end_ms = section_starts[index + 1] if index + 1 < len(section_starts) else source_duration_ms
        operator_trigger_ids = [
            int(event["id"])
            for event, onset in zip(events, event_onsets)
            if start_ms <= onset < end_ms
        ]
        entry_trigger_id = int(events[0]["id"])
        for event, onset in zip(events, event_onsets):
            if onset <= start_ms:
                entry_trigger_id = int(event["id"])
            else:
                break
        sections.append(
            {
                "id": plan.section_id,
                "key": plan.key,
                "label": plan.label,
                "startMeasure": plan.start_measure,
                "endMeasure": plan.end_measure,
                "scoreRange": f"M{plan.start_measure}-M{plan.end_measure}",
                "summary": plan.summary,
                "startAtMs": round(start_ms, 3),
                "endAtMs": round(end_ms, 3),
                "durationMs": round(end_ms - start_ms, 3),
                "entryTriggerId": entry_trigger_id,
                "operatorTriggerIds": operator_trigger_ids,
            }
        )

    for event_index, event in enumerate(events):
        event_start = event_onsets[event_index]
        event_end = event_onsets[event_index + 1] if event_index + 1 < len(events) else source_duration_ms
        windows = []
        for section in sections:
            overlap_start = max(event_start, float(section["startAtMs"]))
            overlap_end = min(event_end, float(section["endAtMs"]))
            if overlap_end <= overlap_start:
                continue
            windows.append(
                {
                    "sectionId": section["id"],
                    "key": section["key"],
                    "label": section["label"],
                    "startAtMs": round(overlap_start - event_start, 3),
                    "endAtMs": round(overlap_end - event_start, 3),
                    "durationMs": round(overlap_end - overlap_start, 3),
                }
            )
        event["visualSectionIds"] = [window["sectionId"] for window in windows]
        event["visualSectionWindows"] = windows

    schema["operatorTriggerCount"] = 12
    schema["visualSectionCount"] = 18
    schema["visualSectionModelVersion"] = 1
    schema["visualSectionTimingBasis"] = (
        "v26 MusicXML measure starts; the final section extends through the source audio duration"
    )
    schema["visualSections"] = sections
    return schema


def main() -> None:
    schema = json.loads(SCHEMA_PATH.read_text())
    updated = build_section_model(schema)
    SCHEMA_PATH.write_text(json.dumps(updated, indent=2) + "\n")
    print(f"Visual sections: {updated['visualSectionCount']}")
    print(f"Operator triggers retained: {updated['operatorTriggerCount']}")
    print(f"Updated schema: {SCHEMA_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
