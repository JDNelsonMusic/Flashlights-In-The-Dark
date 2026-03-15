#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET
from collections import Counter
from datetime import datetime, timezone
from fractions import Fraction
from pathlib import Path
from typing import Any

from score_measure_utils import build_measure_token_map


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RECIPE_JSON = ROOT / "Flashlights-ITD_EventRecipes_4_2026_0309" / "event_recipes.json"
DEFAULT_SCORE_XML = (
    ROOT / "Flashlights-ITD_EventRecipes_4_2026_0309" / "FlashlightsInTheDark_v32_TourCut.musicxml"
)
DEFAULT_OUTPUT_DIR = ROOT / "docs" / "protools-housekeeping"
POSITION_RE = re.compile(r"^(?P<beat>[\d+/]+)-of-(?P<measure_beats>\d+)$")
FFPROBE_CMD = [
    "ffprobe",
    "-v",
    "error",
    "-show_entries",
    "stream=codec_name,sample_rate,channels:format=duration,bit_rate",
    "-of",
    "json",
]
COLOR_TO_SLOTS = {
    "green": "16,29,44",
    "magenta": "12,24,25",
    "orange": "23,38,51",
    "blue": "27,41,42",
    "red": "1,14,15",
    "cyan": "40,53,54",
    "yellow": "7,19,34",
    "pink": "9,20,21",
    "purple": "3,4,18",
}
ASSET_ROOTS = {
    "flutter": ROOT / "flashlights_client" / "available-sounds",
    "macos": ROOT / "FlashlightsInTheDark_MacOS" / "Audio",
}
EVENT_RECIPE_COPIES = {
    "recipe_bundle": ROOT / "Flashlights-ITD_EventRecipes_4_2026_0309" / "event_recipes.json",
    "macos": ROOT / "FlashlightsInTheDark_MacOS" / "Resources" / "event_recipes.json",
    "flutter": ROOT / "flashlights_client" / "assets" / "event_recipes.json",
}


def sample_lookup_key(sample_path: str) -> str:
    return sample_path.replace("\\", "/").lower()


def iso_now() -> str:
    return datetime.now(tz=timezone.utc).isoformat(timespec="seconds")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def human_seconds(value: float) -> str:
    minutes = int(value // 60)
    seconds = value - (minutes * 60)
    return f"{minutes}:{seconds:06.3f}"


def parse_mixed_number(raw: str) -> Fraction:
    if "+" in raw:
        whole, fraction = raw.split("+", 1)
        return Fraction(int(whole)) + Fraction(fraction)
    return Fraction(raw)


def parse_position_offset(position: str, beat_type: int) -> Fraction:
    stripped = position.strip()
    if stripped.lower().startswith("beat"):
        return Fraction(int(stripped[4:]) - 1) * Fraction(4, beat_type)
    match = POSITION_RE.match(stripped)
    if match is None:
        raise ValueError(f"Unsupported position format: {position}")
    beat_value = parse_mixed_number(match.group("beat"))
    return (beat_value - 1) * Fraction(4, beat_type)


def parse_measure_number(raw_measure_number: str) -> int | None:
    match = re.match(r"^(\d+)", raw_measure_number.strip())
    if match is None:
        return None
    return int(match.group(1))


def ffprobe_metadata(path: Path) -> dict[str, Any]:
    try:
        result = subprocess.run(
            FFPROBE_CMD + [str(path)],
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {}

    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}

    format_info = payload.get("format", {})
    streams = payload.get("streams", [])
    first_stream = streams[0] if streams else {}
    metadata: dict[str, Any] = {}

    duration = format_info.get("duration")
    if duration is not None:
        try:
            metadata["duration_seconds"] = round(float(duration), 6)
        except (TypeError, ValueError):
            pass

    bit_rate = format_info.get("bit_rate")
    if bit_rate is not None:
        try:
            metadata["bit_rate"] = int(bit_rate)
        except (TypeError, ValueError):
            pass

    codec_name = first_stream.get("codec_name")
    if codec_name:
        metadata["codec_name"] = codec_name

    sample_rate = first_stream.get("sample_rate")
    if sample_rate is not None:
        try:
            metadata["sample_rate"] = int(sample_rate)
        except (TypeError, ValueError):
            pass

    channels = first_stream.get("channels")
    if channels is not None:
        try:
            metadata["channels"] = int(channels)
        except (TypeError, ValueError):
            pass

    return metadata


def collect_measure_words(measure: ET.Element) -> list[str]:
    words = []
    for word in measure.findall(".//direction-type/words"):
        text = " ".join((word.text or "").split())
        if text:
            words.append(text)
    return words


def build_measure_map(score_xml: Path) -> tuple[list[dict[str, Any]], dict[int, dict[str, Any]]]:
    root = ET.parse(score_xml).getroot()
    first_part = root.find(".//part")
    if first_part is None:
        raise ValueError(f"No part found in {score_xml}")

    beats = 4
    beat_type = 4
    tempo = Fraction(102, 1)
    start_seconds = Fraction(0, 1)
    tempo_map: list[dict[str, Any]] = []
    measure_lookup: dict[int, dict[str, Any]] = {}

    for measure in first_part.findall("measure"):
        measure_number = parse_measure_number(measure.get("number", ""))
        if measure_number is None:
            continue

        attributes = measure.find("attributes")
        if attributes is not None:
            time = attributes.find("time")
            if time is not None:
                beats = int(time.findtext("beats"))
                beat_type = int(time.findtext("beat-type"))

        tempos = [sound.get("tempo") for sound in measure.findall(".//sound") if sound.get("tempo")]
        if tempos:
            tempo = Fraction(tempos[0])

        words = collect_measure_words(measure)
        duration_quarters = Fraction(beats * 4, beat_type)
        duration_seconds = duration_quarters * Fraction(60, 1) / tempo
        entry = {
            "measure": measure_number,
            "start_seconds": round(float(start_seconds), 6),
            "duration_seconds": round(float(duration_seconds), 6),
            "beats": beats,
            "beat_type": beat_type,
            "tempo_bpm": round(float(tempo), 6),
            "words": words,
        }
        tempo_map.append(entry)
        measure_lookup[measure_number] = entry
        start_seconds += duration_seconds

    return tempo_map, measure_lookup


def build_asset_inventory() -> dict[str, dict[str, dict[str, Any]]]:
    inventories: dict[str, dict[str, dict[str, Any]]] = {}
    for label, asset_root in ASSET_ROOTS.items():
        primer_root = asset_root / "primerTones"
        inventory: dict[str, dict[str, Any]] = {}
        if primer_root.exists():
            for path in sorted(primer_root.glob("*.mp3")):
                relative_sample = f"primerTones/{path.name}"
                inventory[sample_lookup_key(relative_sample)] = {
                    "sample": relative_sample,
                    "path": str(path.relative_to(ROOT)),
                    "sha256": sha256_file(path),
                    **ffprobe_metadata(path),
                }
        inventories[label] = inventory
    return inventories


def build_event_recipe_hashes() -> dict[str, dict[str, Any]]:
    hashes: dict[str, dict[str, Any]] = {}
    for label, path in EVENT_RECIPE_COPIES.items():
        hashes[label] = {
            "path": str(path.relative_to(ROOT)),
            "sha256": sha256_file(path),
        }
    return hashes


def timing_note_for_event(event: dict[str, Any], measure_words: list[str]) -> str:
    joined_words = " ".join(measure_words).lower()
    if "aleatoric style" in joined_words:
        return "measure_contains_aleatoric_instruction"
    if event["measure"] >= 115:
        return "post_aleatoric_section_human_validate"
    return "musicxml_tempo_encoded"


def build_timeline(
    recipe_bundle: dict[str, Any],
    measure_lookup: dict[str, dict[str, Any]],
    asset_inventory: dict[str, dict[str, dict[str, Any]]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    event_rows: list[dict[str, Any]] = []
    clip_rows: list[dict[str, Any]] = []
    referenced_samples = set()
    referenced_samples_original: dict[str, str] = {}

    for event in recipe_bundle["events"]:
        measure_token = str(event.get("measureToken") or event["measure"])
        measure_info = measure_lookup[measure_token]
        onset_fraction = parse_position_offset(event["position"], measure_info["beat_type"])
        onset_seconds = measure_info["start_seconds"] + (
            float(onset_fraction) * 60.0 / measure_info["tempo_bpm"]
        )

        primer_assignments = event.get("primer", {})
        electronics_assignments = event.get("electronics", {})
        electronics_by_part = event.get("electronicsByPart", {})
        sample_durations = []
        for color, assignment in primer_assignments.items():
            sample = assignment["sample"]
            sample_key = sample_lookup_key(sample)
            referenced_samples.add(sample_key)
            referenced_samples_original.setdefault(sample_key, sample)
            macos_meta = asset_inventory["macos"].get(sample_key, {})
            flutter_meta = asset_inventory["flutter"].get(sample_key, {})
            sample_duration = (
                macos_meta.get("duration_seconds")
                or flutter_meta.get("duration_seconds")
                or 0.0
            )
            sample_durations.append(sample_duration)
            clip_rows.append(
                {
                    "event_id": event["id"],
                    "measure_token": measure_token,
                    "measure": event["measure"],
                    "position": event["position"],
                    "onset_seconds": round(onset_seconds, 6),
                    "end_seconds": round(onset_seconds + sample_duration, 6),
                    "tempo_bpm": measure_info["tempo_bpm"],
                    "meter": f"{measure_info['beats']}/{measure_info['beat_type']}",
                    "clip_type": "primer",
                    "assignment_key": color,
                    "slots": COLOR_TO_SLOTS.get(color, ""),
                    "sample": sample,
                    "note": assignment["note"],
                    "channel_mode": "",
                    "sample_duration_seconds": sample_duration,
                    "present_in_macos_assets": sample_key in asset_inventory["macos"],
                    "present_in_flutter_assets": sample_key in asset_inventory["flutter"],
                }
            )

        for family, assignment in electronics_assignments.items():
            sample = assignment.get("sample", "")
            sample_duration = float(assignment.get("durationMs", 0.0)) / 1000.0
            sample_durations.append(sample_duration)
            clip_rows.append(
                {
                    "event_id": event["id"],
                    "measure_token": measure_token,
                    "measure": event["measure"],
                    "position": event["position"],
                    "onset_seconds": round(onset_seconds, 6),
                    "end_seconds": round(onset_seconds + sample_duration, 6),
                    "tempo_bpm": measure_info["tempo_bpm"],
                    "meter": f"{measure_info['beats']}/{measure_info['beat_type']}",
                    "clip_type": "electronics",
                    "assignment_key": family,
                    "slots": "",
                    "sample": sample,
                    "note": "",
                    "channel_mode": assignment.get("channelMode", ""),
                    "sample_duration_seconds": sample_duration,
                    "present_in_macos_assets": True,
                    "present_in_flutter_assets": True,
                }
            )

        for part_key, assignment in electronics_by_part.items():
            sample = assignment.get("sample", "")
            sample_duration = float(assignment.get("durationMs", 0.0)) / 1000.0
            sample_durations.append(sample_duration)
            clip_rows.append(
                {
                    "event_id": event["id"],
                    "measure_token": measure_token,
                    "measure": event["measure"],
                    "position": event["position"],
                    "onset_seconds": round(onset_seconds, 6),
                    "end_seconds": round(onset_seconds + sample_duration, 6),
                    "tempo_bpm": measure_info["tempo_bpm"],
                    "meter": f"{measure_info['beats']}/{measure_info['beat_type']}",
                    "clip_type": "electronics_part",
                    "assignment_key": part_key,
                    "slots": "",
                    "sample": sample,
                    "note": assignment.get("designNote", ""),
                    "channel_mode": assignment.get("channelMode", ""),
                    "sample_duration_seconds": sample_duration,
                    "present_in_macos_assets": True,
                    "present_in_flutter_assets": True,
                }
            )

        event_duration = max(sample_durations) if sample_durations else 0.0
        event_rows.append(
            {
                "id": event["id"],
                "measure_token": measure_token,
                "measure": event["measure"],
                "position": event["position"],
                "onset_seconds": round(onset_seconds, 6),
                "onset_milliseconds": round(onset_seconds * 1000),
                "event_duration_seconds": round(event_duration, 6),
                "event_end_seconds": round(onset_seconds + event_duration, 6),
                "tempo_bpm": measure_info["tempo_bpm"],
                "meter": f"{measure_info['beats']}/{measure_info['beat_type']}",
                "primer_count": len(primer_assignments),
                "electronics_count": len(electronics_assignments)
                + len(electronics_by_part),
                "sample_length": (
                    "LONG"
                    if primer_assignments
                    and any("long" in assignment["sample"].lower() for assignment in primer_assignments.values())
                    else ("SHORT" if primer_assignments else "ELECTRONICS")
                ),
                "measure_words": measure_info["words"],
                "timing_note": timing_note_for_event(event, measure_info["words"]),
                "primer": primer_assignments,
                "electronics": electronics_assignments,
                "electronicsByPart": electronics_by_part,
            }
        )

    integration = {
        "referenced_sample_count": len(referenced_samples),
        "missing_in_macos_assets": sorted(
            referenced_samples_original[sample]
            for sample in referenced_samples
            if sample not in asset_inventory["macos"]
        ),
        "missing_in_flutter_assets": sorted(
            referenced_samples_original[sample]
            for sample in referenced_samples
            if sample not in asset_inventory["flutter"]
        ),
        "referenced_samples": sorted(referenced_samples_original[sample] for sample in referenced_samples),
    }
    return event_rows, clip_rows, integration


def compare_primer_assets(asset_inventory: dict[str, dict[str, dict[str, Any]]]) -> dict[str, Any]:
    macos_samples = set(asset_inventory["macos"])
    flutter_samples = set(asset_inventory["flutter"])
    shared_samples = sorted(macos_samples & flutter_samples)
    mismatched_hashes = []
    for sample in shared_samples:
        if asset_inventory["macos"][sample]["sha256"] != asset_inventory["flutter"][sample]["sha256"]:
            mismatched_hashes.append(asset_inventory["macos"][sample]["sample"])

    return {
        "macos_count": len(macos_samples),
        "flutter_count": len(flutter_samples),
        "missing_in_macos": sorted(asset_inventory["flutter"][sample]["sample"] for sample in (flutter_samples - macos_samples)),
        "missing_in_flutter": sorted(asset_inventory["macos"][sample]["sample"] for sample in (macos_samples - flutter_samples)),
        "mismatched_hashes": mismatched_hashes,
    }


def compare_event_recipe_copies(recipe_hashes: dict[str, dict[str, Any]]) -> dict[str, Any]:
    hashes = {label: item["sha256"] for label, item in recipe_hashes.items()}
    return {
        "all_equal": len(set(hashes.values())) == 1,
        "hashes": hashes,
    }


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    fieldnames = list(rows[0].keys()) if rows else []
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            serialized = {
                key: json.dumps(value, ensure_ascii=True) if isinstance(value, (dict, list)) else value
                for key, value in row.items()
            }
            writer.writerow(serialized)


def render_markdown(report: dict[str, Any]) -> str:
    summary = report["summary"]
    lines = [
        "# Event Timeline And Integration Report",
        "",
        f"Generated: `{report['generated_utc']}`",
        f"Recipe source: `{report['sources']['recipe_json']}`",
        f"Score source: `{report['sources']['musicxml']}`",
        "",
        "## Timeline Snapshot",
        "",
        f"- Events: `{summary['event_count']}`",
        f"- Clip rows: `{summary['clip_count']}`",
        f"- Long events: `{summary['long_event_count']}`",
        f"- First event: `{human_seconds(summary['first_event_seconds'])}`",
        f"- Last event: `{human_seconds(summary['last_event_seconds'])}`",
        f"- Score end: `{human_seconds(summary['score_end_seconds'])}`",
        "",
        "## Tempo Map",
        "",
    ]

    for entry in report["tempo_changes"]:
        lines.append(
            f"- Measure `{entry['measure']}` starts at `{human_seconds(entry['start_seconds'])}` with `{entry['tempo_bpm']}` BPM in `{entry['beats']}/{entry['beat_type']}`"
        )

    lines.extend(
        [
            "",
            "## Timing Caveats",
            "",
        ]
    )
    for caveat in report["caveats"]:
        lines.append(f"- {caveat}")

    lines.extend(
        [
            "",
            "## Integration Checks",
            "",
            f"- Event recipe copies identical: `{report['event_recipe_copy_check']['all_equal']}`",
            f"- Primer asset counts: macOS `{report['primer_asset_check']['macos_count']}`, Flutter `{report['primer_asset_check']['flutter_count']}`",
            f"- Referenced samples missing in macOS assets: `{len(report['integration']['missing_in_macos_assets'])}`",
            f"- Referenced samples missing in Flutter assets: `{len(report['integration']['missing_in_flutter_assets'])}`",
            f"- Primer asset hash mismatches across macOS/Flutter: `{len(report['primer_asset_check']['mismatched_hashes'])}`",
            "",
            "## Outputs",
            "",
            "- `event_timeline.json`",
            "- `event_timeline_events.csv`",
            "- `event_timeline_clips.csv`",
            "",
        ]
    )
    return "\n".join(lines)


def build_report(recipe_json: Path, score_xml: Path) -> dict[str, Any]:
    recipe_bundle = json.loads(recipe_json.read_text())
    tempo_map, measure_lookup, _ = build_measure_token_map(score_xml)
    asset_inventory = build_asset_inventory()
    event_recipe_hashes = build_event_recipe_hashes()
    event_rows, clip_rows, integration = build_timeline(
        recipe_bundle=recipe_bundle,
        measure_lookup=measure_lookup,
        asset_inventory=asset_inventory,
    )
    primer_asset_check = compare_primer_assets(asset_inventory)
    event_recipe_copy_check = compare_event_recipe_copies(event_recipe_hashes)

    long_event_count = sum(1 for row in event_rows if row["sample_length"] == "LONG")
    caveats = [
        "Performance-time onsets are exact with respect to the encoded MusicXML tempo and meter map.",
        "The score contains explicit tempo changes at measures 1 (102 BPM) and 30 (72 BPM), with no later encoded tempo changes.",
        "Measures 115 and 130 contain 'articulate freely in aleatoric style'; events in and after that late section should be human-validated if absolute seconds matter in performance.",
        "Clip end times come from the currently bundled trigger assets and may differ from older primer-based reports.",
    ]

    return {
        "generated_utc": iso_now(),
        "sources": {
            "recipe_json": str(recipe_json.relative_to(ROOT)),
            "musicxml": str(score_xml.relative_to(ROOT)),
        },
        "summary": {
            "event_count": len(event_rows),
            "clip_count": len(clip_rows),
            "long_event_count": long_event_count,
            "first_event_seconds": event_rows[0]["onset_seconds"] if event_rows else 0.0,
            "last_event_seconds": event_rows[-1]["onset_seconds"] if event_rows else 0.0,
            "score_end_seconds": (
                tempo_map[-1]["start_seconds"] + tempo_map[-1]["duration_seconds"] if tempo_map else 0.0
            ),
        },
        "tempo_changes": [
            {
                "measure": entry["measureToken"],
                "start_seconds": entry["start_seconds"],
                "tempo_bpm": entry["tempo_bpm"],
                "beats": entry["beats"],
                "beat_type": entry["beat_type"],
            }
            for index, entry in enumerate(tempo_map)
            if index == 0 or tempo_map[index - 1]["tempo_bpm"] != entry["tempo_bpm"]
        ],
        "tempo_map": tempo_map,
        "event_recipe_hashes": event_recipe_hashes,
        "event_recipe_copy_check": event_recipe_copy_check,
        "primer_asset_check": primer_asset_check,
        "integration": integration,
        "caveats": caveats,
        "events": event_rows,
        "clips": clip_rows,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a performance-time event timeline from the recipe bundle and MusicXML score.")
    parser.add_argument(
        "--recipe-json",
        type=Path,
        default=DEFAULT_RECIPE_JSON,
        help="Path to the event recipe JSON bundle.",
    )
    parser.add_argument(
        "--score-xml",
        type=Path,
        default=DEFAULT_SCORE_XML,
        help="Path to the source MusicXML file.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Directory where generated timeline files should be written.",
    )
    args = parser.parse_args()

    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    report = build_report(args.recipe_json.resolve(), args.score_xml.resolve())

    json_path = output_dir / "event_timeline.json"
    events_csv_path = output_dir / "event_timeline_events.csv"
    clips_csv_path = output_dir / "event_timeline_clips.csv"
    md_path = output_dir / "event_timeline.md"

    json_path.write_text(json.dumps(report, indent=2) + "\n")
    write_csv(events_csv_path, report["events"])
    write_csv(clips_csv_path, report["clips"])
    md_path.write_text(render_markdown(report) + "\n")

    print(f"Wrote {json_path.relative_to(ROOT)}")
    print(f"Wrote {events_csv_path.relative_to(ROOT)}")
    print(f"Wrote {clips_csv_path.relative_to(ROOT)}")
    print(f"Wrote {md_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
