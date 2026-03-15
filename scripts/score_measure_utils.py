#!/usr/bin/env python3

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from fractions import Fraction
from pathlib import Path
from typing import Any


MEASURE_TOKEN_RE = re.compile(r"^(\d+(?:\.\d+)?)")


def parse_measure_token(raw_measure_number: str | None) -> str | None:
    if raw_measure_number is None:
        return None
    token = raw_measure_number.strip()
    if not token:
        return None
    match = MEASURE_TOKEN_RE.match(token)
    if match is None:
        return None
    return match.group(1)


def parse_base_measure_number(raw_measure_number: str | None) -> int | None:
    token = parse_measure_token(raw_measure_number)
    if token is None:
        return None
    match = re.match(r"^(\d+)", token)
    if match is None:
        return None
    return int(match.group(1))


def collect_measure_words(measure: ET.Element) -> list[str]:
    words = []
    for word in measure.findall(".//direction-type/words"):
        text = " ".join((word.text or "").split())
        if text:
            words.append(text)
    return words


def build_measure_token_map(
    score_xml: Path,
) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]], dict[int, dict[str, Any]]]:
    root = ET.parse(score_xml).getroot()
    first_part = root.find(".//part")
    if first_part is None:
        raise ValueError(f"No part found in {score_xml}")

    beats = 4
    beat_type = 4
    tempo = Fraction(102, 1)
    start_seconds = Fraction(0, 1)
    tempo_map: list[dict[str, Any]] = []
    token_lookup: dict[str, dict[str, Any]] = {}
    ordinal_lookup: dict[int, dict[str, Any]] = {}

    ordinal = 0
    for measure in first_part.findall("measure"):
        raw_measure_number = measure.get("number", "")
        measure_token = parse_measure_token(raw_measure_number)
        base_measure = parse_base_measure_number(raw_measure_number)
        if measure_token is None or base_measure is None:
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
        ordinal += 1
        entry = {
            "measureToken": measure_token,
            "measure": base_measure,
            "ordinal": ordinal,
            "start_seconds": round(float(start_seconds), 6),
            "duration_seconds": round(float(duration_seconds), 6),
            "beats": beats,
            "beat_type": beat_type,
            "tempo_bpm": round(float(tempo), 6),
            "words": words,
        }
        tempo_map.append(entry)
        token_lookup[measure_token] = entry
        ordinal_lookup[ordinal] = entry
        start_seconds += duration_seconds

    return tempo_map, token_lookup, ordinal_lookup
