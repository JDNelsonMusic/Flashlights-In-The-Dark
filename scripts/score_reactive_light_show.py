#!/usr/bin/env python3
"""Score-derived lighting analysis and manifest generation."""

from __future__ import annotations

import json
import math
import re
import xml.etree.ElementTree as ET
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from typing import Any


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

LIGHT_VOICE_MAP = {
    "soprano_l1": ("P4", "1"),
    "soprano_l2": ("P4", "2"),
    "alto_l1": ("P5", "1"),
    "alto_l2": ("P5", "2"),
    "tenor_l": ("P6", "1"),
    "bass_l": ("P6", "2"),
}

DYNAMIC_LEVELS = {
    "pppp": 0.08,
    "ppp": 0.12,
    "pp": 0.18,
    "p": 0.28,
    "mp": 0.42,
    "mf": 0.58,
    "f": 0.74,
    "ff": 0.88,
    "fff": 1.0,
}

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


@dataclass(frozen=True)
class TempoMark:
    beat: float
    bpm: float


@dataclass(frozen=True)
class ScoreNote:
    group_key: str
    part_id: str
    voice: str
    measure: int
    onset_beats: float
    duration_beats: float
    score_ms: float
    duration_ms: float
    midi: int
    pitch: str
    measure_downbeat: bool


@dataclass(frozen=True)
class ScoreText:
    measure: int
    beat: float
    text: str


@dataclass(frozen=True)
class ScoreDynamic:
    measure: int
    beat: float
    value: str
    level: float


def _measure_base_number(raw: str | None) -> int | None:
    if raw is None:
        return None
    match = re.match(r"^(\d+)", raw.strip())
    if match is None:
        return None
    return int(match.group(1))


def _pitch(note: ET.Element) -> tuple[int, str]:
    pitch = note.find("pitch")
    if pitch is None:
        raise ValueError("Expected pitched note")
    step = pitch.findtext("step")
    octave = pitch.findtext("octave")
    if step is None or octave is None:
        raise ValueError("Incomplete pitch element")
    alter = int(pitch.findtext("alter", "0"))
    midi = 12 * (int(octave) + 1) + STEP_TO_SEMITONE[step] + alter
    return midi, f"{step}{ALTER_TO_ACCIDENTAL.get(alter, f'({alter})')}{octave}"


def _measure_duration_and_directions(
    measure: ET.Element,
    *,
    divisions: int,
    measure_start_beats: float,
) -> tuple[float, int, list[TempoMark], list[ScoreText], list[ScoreDynamic]]:
    cursor = 0
    max_cursor = 0
    local_divisions = divisions
    tempos: list[TempoMark] = []
    texts: list[ScoreText] = []
    dynamics: list[ScoreDynamic] = []
    measure_number = _measure_base_number(measure.attrib.get("number"))

    for child in measure:
        if child.tag == "attributes":
            if child.findtext("divisions"):
                local_divisions = int(child.findtext("divisions"))
            continue
        if child.tag == "backup":
            cursor -= int(child.findtext("duration", "0"))
            continue
        if child.tag == "forward":
            cursor += int(child.findtext("duration", "0"))
            max_cursor = max(max_cursor, cursor)
            continue
        if child.tag == "direction":
            beat = measure_start_beats + cursor / max(local_divisions, 1)
            sound = child.find("sound")
            if sound is not None and sound.attrib.get("tempo"):
                tempos.append(TempoMark(beat=beat, bpm=float(sound.attrib["tempo"])))
            for direction_type in child.findall("direction-type"):
                words = direction_type.find("words")
                if words is not None and words.text and measure_number is not None:
                    texts.append(
                        ScoreText(
                            measure=measure_number,
                            beat=beat,
                            text=" ".join(words.text.split()),
                        )
                    )
                dynamic = direction_type.find("dynamics")
                if dynamic is not None and measure_number is not None:
                    for item in dynamic:
                        level = DYNAMIC_LEVELS.get(item.tag)
                        if level is not None:
                            dynamics.append(
                                ScoreDynamic(
                                    measure=measure_number,
                                    beat=beat,
                                    value=item.tag,
                                    level=level,
                                )
                            )
            continue
        if child.tag != "note":
            continue

        duration = int(child.findtext("duration", "0"))
        if child.find("chord") is None:
            cursor += duration
            max_cursor = max(max_cursor, cursor)

    return max_cursor / max(local_divisions, 1), local_divisions, tempos, texts, dynamics


def _extract_measure_map(
    parts: dict[str, ET.Element],
) -> tuple[dict[int, float], list[TempoMark], list[ScoreText], list[ScoreDynamic]]:
    reference = parts.get("P1")
    if reference is None:
        reference = next(iter(parts.values()))
    divisions = 1
    current_beat = 0.0
    measure_starts: dict[int, float] = {}
    tempos: list[TempoMark] = []
    texts: list[ScoreText] = []
    dynamics: list[ScoreDynamic] = []

    for measure in reference.findall("measure"):
        measure_number = _measure_base_number(measure.attrib.get("number"))
        if measure_number is None:
            continue
        measure_starts[measure_number] = current_beat
        duration, divisions, measure_tempos, measure_texts, measure_dynamics = _measure_duration_and_directions(
            measure,
            divisions=divisions,
            measure_start_beats=current_beat,
        )
        tempos.extend(measure_tempos)
        texts.extend(measure_texts)
        dynamics.extend(measure_dynamics)
        current_beat += duration

    if not tempos or tempos[0].beat > 0:
        tempos.insert(0, TempoMark(beat=0.0, bpm=102.0))
    tempos.sort(key=lambda item: item.beat)
    return measure_starts, tempos, texts, dynamics


def _beats_to_ms(beat: float, tempos: list[TempoMark]) -> float:
    total_ms = 0.0
    for index, mark in enumerate(tempos):
        next_beat = tempos[index + 1].beat if index + 1 < len(tempos) else beat
        if beat <= mark.beat:
            break
        segment_end = min(beat, next_beat)
        if segment_end > mark.beat:
            total_ms += (segment_end - mark.beat) * 60000.0 / mark.bpm
        if beat <= next_beat:
            break
    return total_ms


def _extract_group_notes(
    parts: dict[str, ET.Element],
    measure_starts: dict[int, float],
    tempos: list[TempoMark],
) -> list[ScoreNote]:
    notes: list[ScoreNote] = []
    for group_key, (part_id, target_voice) in LIGHT_VOICE_MAP.items():
        part = parts[part_id]
        divisions = 1
        for measure in part.findall("measure"):
            measure_number = _measure_base_number(measure.attrib.get("number"))
            if measure_number is None or measure_number not in measure_starts:
                continue
            measure_start = measure_starts[measure_number]
            cursor = 0
            last_note_onset = 0
            for child in measure:
                if child.tag == "attributes":
                    if child.findtext("divisions"):
                        divisions = int(child.findtext("divisions"))
                    continue
                if child.tag == "backup":
                    cursor -= int(child.findtext("duration", "0"))
                    continue
                if child.tag == "forward":
                    cursor += int(child.findtext("duration", "0"))
                    continue
                if child.tag != "note":
                    continue

                duration = int(child.findtext("duration", "0"))
                is_chord = child.find("chord") is not None
                onset_cursor = last_note_onset if is_chord else cursor
                voice = child.findtext("voice", "1")
                is_rest = child.find("rest") is not None

                if voice == target_voice and not is_rest and not is_chord:
                    midi, pitch = _pitch(child)
                    onset_beats = measure_start + onset_cursor / max(divisions, 1)
                    duration_beats = duration / max(divisions, 1)
                    score_ms = _beats_to_ms(onset_beats, tempos)
                    end_ms = _beats_to_ms(onset_beats + duration_beats, tempos)
                    notes.append(
                        ScoreNote(
                            group_key=group_key,
                            part_id=part_id,
                            voice=target_voice,
                            measure=measure_number,
                            onset_beats=onset_beats,
                            duration_beats=duration_beats,
                            score_ms=score_ms,
                            duration_ms=max(1.0, end_ms - score_ms),
                            midi=midi,
                            pitch=pitch,
                            measure_downbeat=onset_cursor == 0,
                        )
                    )

                if not is_chord:
                    last_note_onset = cursor
                    cursor += duration
    notes.sort(key=lambda item: (item.score_ms, item.group_key, item.midi))
    return notes


def _recent_dynamic_level(
    dynamics: list[ScoreDynamic],
    *,
    start_beat: float,
    end_beat: float,
) -> tuple[str, float]:
    candidates = [item for item in dynamics if item.beat <= end_beat]
    if not candidates:
        return "mp", DYNAMIC_LEVELS["mp"]
    in_window = [item for item in candidates if start_beat <= item.beat <= end_beat]
    selected = in_window[-1] if in_window else candidates[-1]
    return selected.value, selected.level


def _trigger_duration_ms(trigger_events: list[dict[str, Any]], index: int, source_duration_ms: float) -> float:
    onset = float(trigger_events[index]["onsetMilliseconds"])
    if index + 1 < len(trigger_events):
        return float(trigger_events[index + 1]["onsetMilliseconds"]) - onset
    return source_duration_ms - onset


def build_score_light_analysis(
    *,
    score_path: Path,
    trigger_manifest_path: Path,
    baseline_light_show_path: Path,
) -> dict[str, Any]:
    score_root = ET.parse(score_path).getroot()
    parts = {part.attrib["id"]: part for part in score_root.findall("part")}
    measure_starts, tempos, texts, dynamics = _extract_measure_map(parts)
    notes = _extract_group_notes(parts, measure_starts, tempos)
    trigger_manifest = json.loads(trigger_manifest_path.read_text(encoding="utf-8"))
    baseline = json.loads(baseline_light_show_path.read_text(encoding="utf-8"))
    baseline_events = {int(event["id"]): event for event in baseline["events"]}
    source_duration_ms = float(trigger_manifest["sourceDurationMs"])

    triggers: list[dict[str, Any]] = []
    for index, event in enumerate(trigger_manifest["events"]):
        event_id = int(event["id"])
        start_ms = float(event["onsetMilliseconds"])
        baseline_duration = float(baseline_events.get(event_id, {}).get("durationMs") or 0.0)
        duration_ms = baseline_duration or _trigger_duration_ms(trigger_manifest["events"], index, source_duration_ms)
        end_ms = start_ms + duration_ms
        start_beat = min((note.onset_beats for note in notes if note.score_ms >= start_ms), default=0.0)
        end_beat = max((note.onset_beats for note in notes if note.score_ms <= end_ms), default=start_beat)
        dynamic_name, dynamic_level = _recent_dynamic_level(dynamics, start_beat=start_beat, end_beat=end_beat)
        event_texts = sorted(
            {item.text for item in texts if start_beat <= item.beat <= end_beat},
            key=str.lower,
        )

        parts_payload: dict[str, Any] = {}
        all_midis: list[int] = []
        total_notes = 0
        for group_key in PART_ORDER:
            group_notes = [
                note for note in notes
                if note.group_key == group_key and start_ms <= note.score_ms < end_ms
            ]
            payload_notes = []
            for note in group_notes:
                all_midis.append(note.midi)
                payload_notes.append(
                    {
                        "relativeMs": round(note.score_ms - start_ms, 3),
                        "durationMs": round(note.duration_ms, 3),
                        "measure": note.measure,
                        "midi": note.midi,
                        "pitch": note.pitch,
                        "measureDownbeat": note.measure_downbeat,
                    }
                )
            total_notes += len(payload_notes)
            parts_payload[group_key] = {
                "noteCount": len(payload_notes),
                "densityPerSecond": round(len(payload_notes) / max(duration_ms / 1000.0, 0.001), 4),
                "notes": payload_notes,
            }

        contour = 0
        if len(all_midis) >= 2:
            contour = all_midis[-1] - all_midis[0]
        triggers.append(
            {
                "id": event_id,
                "measure": event.get("measure"),
                "measureToken": event.get("measureToken"),
                "scoreLabel": event.get("scoreLabel"),
                "startScoreMs": round(start_ms, 3),
                "durationMs": round(duration_ms, 3),
                "dynamic": dynamic_name,
                "dynamicLevel": round(dynamic_level, 3),
                "textCues": event_texts,
                "noteCount": total_notes,
                "densityPerSecond": round(total_notes / max(duration_ms / 1000.0, 0.001), 4),
                "register": {
                    "minMidi": min(all_midis) if all_midis else None,
                    "maxMidi": max(all_midis) if all_midis else None,
                    "averageMidi": round(sum(all_midis) / len(all_midis), 3) if all_midis else None,
                    "contour": contour,
                },
                "parts": parts_payload,
            }
        )

    return {
        "analysisVersion": 1,
        "sourceMusicXml": str(score_path),
        "sourceTriggerManifest": str(trigger_manifest_path),
        "baselineLightShow": str(baseline_light_show_path),
        "tempoMap": [{"beat": item.beat, "bpm": item.bpm} for item in tempos],
        "partOrder": PART_ORDER,
        "triggers": triggers,
    }


def _clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def _base_level(points: list[dict[str, float]], duration_ms: float, at_ms: float) -> float:
    if not points:
        return 0.0
    scaled = [(float(point["at"]) * duration_ms, float(point["level"])) for point in points]
    if at_ms <= scaled[0][0]:
        return scaled[0][1]
    for index in range(1, len(scaled)):
        left_t, left_level = scaled[index - 1]
        right_t, right_level = scaled[index]
        if at_ms <= right_t:
            span = max(right_t - left_t, 1.0)
            progress = (at_ms - left_t) / span
            return left_level + (right_level - left_level) * progress
    return scaled[-1][1]


def _density_filtered_notes(notes: list[dict[str, Any]], *, min_gap_ms: float, mode: str) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    last_ms = -10**9
    for note in notes:
        relative_ms = float(note["relativeMs"])
        gap = relative_ms - last_ms
        if mode == "isolated_pools":
            if float(note.get("durationMs", 0.0)) < 500.0 and not bool(note.get("measureDownbeat")):
                continue
        if gap >= min_gap_ms or bool(note.get("measureDownbeat")):
            selected.append(note)
            last_ms = relative_ms
    return selected


def _compose_keyframes(
    *,
    duration_ms: float,
    base_envelope: list[dict[str, float]],
    pulses: list[tuple[float, float, float]],
) -> list[dict[str, float | str]]:
    times = {0.0, round(duration_ms, 3)}
    for point in base_envelope:
        times.add(round(float(point["at"]) * duration_ms, 3))
    for start, end, _ in pulses:
        times.add(round(_clamp(start, 0.0, duration_ms), 3))
        times.add(round(_clamp(end, 0.0, duration_ms), 3))

    keyframes: list[dict[str, float | str]] = []
    for raw_time in sorted(times):
        active = [level for start, end, level in pulses if start <= raw_time < end]
        level = max([_base_level(base_envelope, duration_ms, raw_time), *active])
        starts_pulse = any(math.isclose(start, raw_time, abs_tol=0.75) for start, _, _ in pulses)
        entry: dict[str, float | str] = {
            "atMs": round(raw_time, 3),
            "level": round(_clamp(level), 3),
        }
        if starts_pulse:
            entry["interpolation"] = "step"
        keyframes.append(entry)

    if keyframes:
        keyframes[0]["atMs"] = 0.0
        keyframes[-1]["atMs"] = round(duration_ms, 3)
        keyframes[-1]["level"] = 0.0
    return _dedupe_keyframes(keyframes)


def _dedupe_keyframes(keyframes: list[dict[str, float | str]]) -> list[dict[str, float | str]]:
    deduped: dict[float, dict[str, float | str]] = {}
    for keyframe in keyframes:
        key = round(float(keyframe["atMs"]), 3)
        existing = deduped.get(key)
        if existing is None or float(keyframe["level"]) >= float(existing["level"]):
            deduped[key] = keyframe
    return [deduped[key] for key in sorted(deduped)]


def _part_payload(
    *,
    group_key: str,
    trigger: dict[str, Any],
    params: dict[str, Any],
    duration_ms: float,
) -> dict[str, Any]:
    mode = str(params.get("mode", "phrase_contour"))
    brightness_min = float(params.get("brightnessMin", 0.08))
    brightness_max = float(params.get("brightnessMax", 0.45))
    pulse_ms = float(params.get("pulseMs", 130.0))
    afterglow_ms = float(params.get("afterglowMs", 220.0))
    density_hz = float(params.get("densityLimitHz", 4.0))
    min_gap_ms = 1000.0 / max(density_hz, 0.1)
    group_notes = trigger["parts"][group_key]["notes"]
    selected_notes = _density_filtered_notes(group_notes, min_gap_ms=min_gap_ms, mode=mode)
    base_envelope = params.get("baseEnvelope", [{"at": 0.0, "level": 0.0}, {"at": 1.0, "level": 0.0}])
    dynamic_level = float(trigger.get("dynamicLevel", 0.42))
    register_min = trigger.get("register", {}).get("minMidi") or 48
    register_max = trigger.get("register", {}).get("maxMidi") or 84
    register_span = max(float(register_max - register_min), 1.0)
    pulses: list[tuple[float, float, float]] = []

    for note in selected_notes:
        start = float(note["relativeMs"])
        note_duration = float(note.get("durationMs", pulse_ms))
        register_factor = 0.84 + 0.24 * ((float(note["midi"]) - float(register_min)) / register_span)
        accent = 1.12 if bool(note.get("measureDownbeat")) else 1.0
        section_progress = start / max(duration_ms, 1.0)
        crescendo = 0.72 + 0.42 * section_progress if mode == "density_crescendo" else 1.0
        level = _clamp(
            brightness_min
            + (brightness_max - brightness_min) * max(dynamic_level, 0.22) * register_factor * accent * crescendo
        )
        width = pulse_ms
        if mode in {"breath", "phrase_contour", "exhale", "unified_then_split"}:
            width = min(max(pulse_ms, note_duration * 0.36), afterglow_ms)
        if mode == "isolated_pools":
            width = min(max(pulse_ms, note_duration * 0.65), afterglow_ms * 2.0)
        pulses.append((start, min(duration_ms, start + width), level))

    keyframes = _compose_keyframes(
        duration_ms=duration_ms,
        base_envelope=base_envelope,
        pulses=pulses,
    )
    peak_level = max((float(item["level"]) for item in keyframes), default=0.0)
    return {
        "label": PART_LABELS[group_key],
        "summary": str(params.get("partSummary", "Score-reactive lighting generated from MusicXML activity.")),
        "motion": mode,
        "peakLevel": round(peak_level, 3),
        "durationMs": round(duration_ms, 3),
        "keyframes": keyframes,
    }


def build_score_reactive_manifest(
    *,
    baseline_light_show: dict[str, Any],
    analysis: dict[str, Any],
    grammar: dict[str, Any],
    analysis_path: Path,
    grammar_path: Path,
) -> dict[str, Any]:
    triggers = {int(trigger["id"]): trigger for trigger in analysis["triggers"]}
    grammar_events = grammar.get("events", {})
    result = deepcopy(baseline_light_show)
    result["generated"] = "score-reactive-review-v1"
    result["scoreLightAnalysis"] = str(analysis_path)
    result["scoreReactiveGrammar"] = str(grammar_path)
    result["designNote"] = (
        "Review-only score-reactive draft. Triggers 1-11 are generated from MusicXML-derived "
        "note, dynamic, text, register, density, and phrase data. Trigger 12 is preserved from "
        "the accepted note-synchronous finale."
    )

    new_events: list[dict[str, Any]] = []
    for event in baseline_light_show["events"]:
        event_id = int(event["id"])
        if event_id == 12:
            new_events.append(deepcopy(event))
            continue
        trigger = triggers[event_id]
        params = grammar_events.get(str(event_id), grammar.get("defaults", {}))
        duration_ms = float(event["durationMs"])
        parts = {
            group_key: _part_payload(
                group_key=group_key,
                trigger=trigger,
                params=params,
                duration_ms=duration_ms,
            )
            for group_key in PART_ORDER
        }
        replacement = deepcopy(event)
        replacement["summary"] = params.get("summary", event.get("summary", "Score-reactive light event."))
        replacement["scoreDynamics"] = trigger.get("dynamic", event.get("scoreDynamics", ""))
        replacement["designTags"] = sorted(
            set([*event.get("designTags", []), *params.get("tags", []), "score_reactive"])
        )
        replacement["parts"] = parts
        replacement["scoreReactiveSource"] = {
            "noteCount": trigger["noteCount"],
            "densityPerSecond": trigger["densityPerSecond"],
            "textCues": trigger["textCues"],
            "dynamic": trigger["dynamic"],
        }
        new_events.append(replacement)

    result["events"] = new_events
    return result


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
