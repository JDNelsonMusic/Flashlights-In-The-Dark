#!/usr/bin/env python3
"""Render a six-dot light-show demo video from the active show data."""

from __future__ import annotations

import argparse
import csv
import json
import math
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_AUDIO = (
    ROOT
    / "audio"
    / "protools-exports"
    / "electronics"
    / "2026_0314_FlashlightsInTheDark_Electronics-StereoSum_7.mp3"
)
DEFAULT_LIGHT_SHOW = ROOT / "Engraving" / "Score-Study" / "twelve_trigger_light_show.json"
DEFAULT_TIMING_CSV = ROOT / "DAW-Production" / "Audits" / "electronics_trigger_assets.csv"
DEFAULT_OUTPUT = ROOT / "Visual-Production" / "Demos" / "flashlights_full_version_light_show_demo_draft4_authored_sync.mp4"
DEFAULT_WAVEFORM_AUDIT = ROOT / "Visual-Production" / "Demos" / "flashlights_waveform_alignment_audit_draft4.png"
DEFAULT_TRANSIENT_CSV = ROOT / "Visual-Production" / "Demos" / "flashlights_audio_transients_draft4_reference.csv"
DEFAULT_SCORE_ANALYSIS = ROOT / "Engraving" / "Score-Study" / "score_light_analysis_full_version.json"

STAGE_COLORS = {
    "soprano_l1": (41, 240, 0),
    "soprano_l2": (255, 0, 215),
    "tenor_l": (240, 173, 0),
    "bass_l": (255, 184, 217),
    "alto_l2": (240, 8, 0),
    "alto_l1": (8, 0, 240),
}


@dataclass(frozen=True)
class StageGroup:
    key: str
    label: str
    x: int


@dataclass(frozen=True)
class LightSegment:
    start: float
    end: float
    level_a: float
    level_b: float
    interpolation: str = "linear"


@dataclass(frozen=True)
class CueWindow:
    start: float
    end: float
    label: str


@dataclass(frozen=True)
class TransientPeak:
    time: float
    strength: float
    source: str


@dataclass(frozen=True)
class AuthoredPulse:
    time: float
    group_key: str
    level: float


@dataclass(frozen=True)
class ScoreLandmark:
    time: float
    group_key: str


def run(command: list[str]) -> str:
    completed = subprocess.run(
        command,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return completed.stdout.strip()


def audio_duration_seconds(path: Path) -> float:
    output = run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ]
    )
    return float(output)


def decode_audio_mono(path: Path, sample_rate: int) -> Any:
    import numpy as np

    raw = subprocess.check_output(
        [
            "ffmpeg",
            "-v",
            "error",
            "-i",
            str(path),
            "-f",
            "f32le",
            "-ac",
            "1",
            "-ar",
            str(sample_rate),
            "pipe:1",
        ]
    )
    return np.frombuffer(raw, dtype=np.float32)


def compute_onset_flux(samples: Any, sample_rate: int) -> tuple[Any, Any]:
    import numpy as np

    frame_length = 1024
    hop_length = 256
    frame_count = 1 + (len(samples) - frame_length) // hop_length
    if frame_count <= 1:
        return np.array([], dtype=np.float32), np.array([], dtype=np.float32)

    windows = np.lib.stride_tricks.as_strided(
        samples,
        shape=(frame_count, frame_length),
        strides=(samples.strides[0] * hop_length, samples.strides[0]),
    )
    hann = np.hanning(frame_length).astype(np.float32)
    magnitude = np.abs(np.fft.rfft(windows * hann, axis=1))
    log_magnitude = np.log1p(20.0 * magnitude)
    flux = np.maximum(np.diff(log_magnitude, axis=0, prepend=log_magnitude[:1]), 0.0).sum(axis=1)
    flux = np.convolve(flux, np.ones(3, dtype=np.float32) / 3.0, mode="same")
    times = np.arange(len(flux), dtype=np.float32) * hop_length / float(sample_rate)
    return times, flux.astype(np.float32)


def detect_peaks(
    times: Any,
    flux: Any,
    *,
    percentile: float,
    min_distance_seconds: float,
    start_seconds: float = 0.0,
    end_seconds: float | None = None,
    threshold_scope: str = "global",
    source: str,
) -> list[TransientPeak]:
    import numpy as np

    if len(times) == 0:
        return []
    if end_seconds is None:
        end_seconds = float(times[-1])

    mask = (times >= start_seconds) & (times <= end_seconds)
    threshold_values = flux[mask] if threshold_scope == "window" else flux
    threshold_values = threshold_values[threshold_values > 0]
    if len(threshold_values) == 0:
        return []
    threshold = float(np.percentile(threshold_values, percentile))
    min_distance_frames = max(1, round(min_distance_seconds / float(times[1] - times[0])))

    raw_peaks: list[int] = []
    last_index = -10**9
    for index in range(1, len(flux) - 1):
        if times[index] < start_seconds or times[index] > end_seconds:
            continue
        if index - last_index < min_distance_frames:
            continue
        if flux[index] >= threshold and flux[index] >= flux[index - 1] and flux[index] > flux[index + 1]:
            raw_peaks.append(index)
            last_index = index

    if not raw_peaks:
        return []
    strengths = flux[raw_peaks]
    low = float(np.percentile(strengths, 10))
    high = float(np.percentile(strengths, 95))
    span = max(high - low, 1e-6)
    return [
        TransientPeak(
            time=float(times[index]),
            strength=max(0.0, min(1.0, (float(flux[index]) - low) / span)),
            source=source,
        )
        for index in raw_peaks
    ]


def write_transient_csv(path: Path, global_peaks: list[TransientPeak], final_peaks: list[TransientPeak]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["source", "time_seconds", "strength"])
        writer.writeheader()
        for peak in [*global_peaks, *final_peaks]:
            writer.writerow(
                {
                    "source": peak.source,
                    "time_seconds": f"{peak.time:.6f}",
                    "strength": f"{peak.strength:.6f}",
                }
            )


def load_trigger_starts(path: Path) -> dict[int, float]:
    starts: dict[int, float] = {}
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            event_id = int(row["id"])
            starts.setdefault(event_id, float(row["sourceStartMs"]) / 1000.0)
    return starts


def load_light_show(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def collect_authored_pulses(
    light_show: dict[str, Any],
    starts: dict[int, float],
    *,
    event_id: int,
) -> list[AuthoredPulse]:
    event = next((item for item in light_show["events"] if int(item["id"]) == event_id), None)
    if event is None or event_id not in starts:
        return []

    event_start = starts[event_id]
    pulses: list[AuthoredPulse] = []
    for group_key, part in event.get("parts", {}).items():
        for keyframe in part.get("keyframes", []):
            level = float(keyframe.get("level", 0.0))
            if level <= 0:
                continue
            pulses.append(
                AuthoredPulse(
                    time=event_start + float(keyframe["atMs"]) / 1000.0,
                    group_key=group_key,
                    level=level,
                )
            )
    pulses.sort(key=lambda item: item.time)
    return pulses


def load_score_landmarks(path: Path, starts: dict[int, float]) -> list[ScoreLandmark]:
    if not path.exists():
        return []
    data = load_light_show(path)
    landmarks: list[ScoreLandmark] = []
    for trigger in data.get("triggers", []):
        event_id = int(trigger["id"])
        if event_id not in starts:
            continue
        event_start = starts[event_id]
        for group_key, payload in trigger.get("parts", {}).items():
            for note in payload.get("notes", []):
                landmarks.append(
                    ScoreLandmark(
                        time=event_start + float(note["relativeMs"]) / 1000.0,
                        group_key=group_key,
                    )
                )
    landmarks.sort(key=lambda item: item.time)
    return landmarks


def build_groups(stage_order: list[dict[str, str]], width: int) -> list[StageGroup]:
    margin = int(width * 0.15)
    span = width - margin * 2
    step = span / (len(stage_order) - 1)
    return [
        StageGroup(key=item["key"], label=item["label"], x=round(margin + index * step))
        for index, item in enumerate(stage_order)
    ]


def keyframe_segments(
    keyframes: list[dict[str, float]],
    start_seconds: float,
    *,
    time_scale: float = 1.0,
) -> list[LightSegment]:
    segments: list[LightSegment] = []
    sorted_frames = sorted(keyframes, key=lambda item: float(item["atMs"]))
    for first, second in zip(sorted_frames, sorted_frames[1:]):
        start = start_seconds + (float(first["atMs"]) * time_scale) / 1000.0
        end = start_seconds + (float(second["atMs"]) * time_scale) / 1000.0
        level_a = float(first["level"])
        level_b = float(second["level"])
        if end > start and (level_a > 0 or level_b > 0):
            segments.append(
                LightSegment(
                    start=start,
                    end=end,
                    level_a=level_a,
                    level_b=level_b,
                    interpolation=str(first.get("interpolation", "linear")),
                )
            )
    return segments


def build_timelines(
    light_show: dict[str, Any],
    starts: dict[int, float],
    groups: list[StageGroup],
    duration: float,
    *,
    stretch_final_event_to_audio_tail: bool,
    final_audio_peaks: list[TransientPeak] | None = None,
) -> tuple[dict[str, list[LightSegment]], list[CueWindow], dict[str, float]]:
    timelines = {group.key: [] for group in groups}
    cue_windows: list[CueWindow] = []
    sync_notes: dict[str, float] = {}
    final_audio_start = final_audio_peaks[0].time if final_audio_peaks else None
    events = light_show["events"]
    for event_index, event in enumerate(events):
        event_id = int(event["id"])
        if event_id not in starts:
            continue
        if final_audio_peaks and event_index == len(events) - 1:
            continue
        event_start = starts[event_id]
        declared_duration_ms = float(event.get("durationMs", 0))
        time_scale = 1.0
        effective_duration_ms = declared_duration_ms
        if (
            stretch_final_event_to_audio_tail
            and event_index == len(events) - 1
            and declared_duration_ms > 0
        ):
            audio_tail_ms = max(0.0, (duration - event_start) * 1000.0)
            if audio_tail_ms > declared_duration_ms:
                time_scale = audio_tail_ms / declared_duration_ms
                effective_duration_ms = audio_tail_ms
                sync_notes = {
                    "finalEventId": float(event_id),
                    "finalEventStartSeconds": event_start,
                    "declaredFinalDurationSeconds": declared_duration_ms / 1000.0,
                    "audioTailDurationSeconds": audio_tail_ms / 1000.0,
                    "finalEventTimeScale": time_scale,
                }
        event_end = min(duration, event_start + effective_duration_ms / 1000.0)
        cue_windows.append(
            CueWindow(
                start=event_start,
                end=min(duration, event_end + 0.8),
                label=f"Trigger {event_id:02d} - {event.get('scoreLabel', '')}",
            )
        )
        parts = event.get("parts", {})
        for group in groups:
            part = parts.get(group.key)
            if part:
                timelines[group.key].extend(
                    keyframe_segments(
                        part.get("keyframes", []),
                        event_start,
                        time_scale=time_scale,
                    )
                )

    if final_audio_peaks:
        assert final_audio_start is not None
        final_audio_end = min(duration, final_audio_peaks[-1].time + 0.45)
        for group in groups:
            truncated: list[LightSegment] = []
            for segment in timelines[group.key]:
                if segment.end <= final_audio_start:
                    truncated.append(segment)
                elif segment.start < final_audio_start:
                    truncated.append(
                        LightSegment(
                            start=segment.start,
                            end=final_audio_start,
                            level_a=segment.level_a,
                            level_b=0.0,
                            interpolation=segment.interpolation,
                        )
                    )
            timelines[group.key] = truncated

        trimmed_cues: list[CueWindow] = []
        for cue in cue_windows:
            if cue.end <= final_audio_start:
                trimmed_cues.append(cue)
            elif cue.start < final_audio_start:
                trimmed_cues.append(
                    CueWindow(
                        start=cue.start,
                        end=final_audio_start,
                        label=cue.label,
                    )
                )
        cue_windows = trimmed_cues

        for peak in final_audio_peaks:
            pulse_peak = 0.52 + 0.34 * peak.strength
            for group in groups:
                timelines[group.key].append(
                    LightSegment(
                        start=peak.time,
                        end=min(duration, peak.time + 0.22),
                        level_a=pulse_peak,
                        level_b=0.0,
                        interpolation="linear",
                    )
                )
        cue_windows.append(
            CueWindow(
                start=final_audio_start,
                end=final_audio_end,
                label="Audio-synced final articulations",
            )
        )
        sync_notes = {
            "finalAudioPeakCount": float(len(final_audio_peaks)),
            "finalAudioStartSeconds": final_audio_start,
            "finalAudioEndSeconds": final_audio_peaks[-1].time,
            "finalAudioWindowEndSeconds": final_audio_end,
        }

    for segments in timelines.values():
        segments.sort(key=lambda item: item.start)
    cue_windows.sort(key=lambda item: item.start)
    return timelines, cue_windows, sync_notes


def level_at_time(segments: list[LightSegment], index: int, t: float) -> tuple[float, int]:
    while index < len(segments) and t >= segments[index].end:
        index += 1
    if index >= len(segments):
        return 0.0, index
    segment = segments[index]
    if segment.start <= t < segment.end:
        if segment.interpolation == "step":
            return min(max(segment.level_a, 0.0), 1.0), index
        progress = (t - segment.start) / (segment.end - segment.start)
        level = segment.level_a + (segment.level_b - segment.level_a) * progress
        return min(max(level, 0.0), 1.0), index
    return 0.0, index


def cue_at_time(cues: list[CueWindow], index: int, t: float) -> tuple[str | None, int]:
    while index < len(cues) and t >= cues[index].end:
        index += 1
    if index < len(cues) and cues[index].start <= t < cues[index].end:
        return cues[index].label, index
    return None, index


def load_pillow() -> tuple[Any, Any, Any]:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ModuleNotFoundError as error:
        raise SystemExit(
            "This renderer needs Pillow. Run it with the bundled Codex Python runtime "
            "or install Pillow into your active Python environment."
        ) from error
    return Image, ImageDraw, ImageFont


def load_font(image_font: Any, size: int, *, bold: bool = False) -> Any:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Avenir.ttc",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            try:
                return image_font.truetype(candidate, size=size)
            except OSError:
                pass
    return image_font.load_default(size=size)


def draw_centered(draw: Any, xy: tuple[int, int], text: str, font: Any, fill: tuple[int, int, int, int]) -> None:
    x, y = xy
    bbox = draw.textbbox((0, 0), text, font=font)
    width = bbox[2] - bbox[0]
    height = bbox[3] - bbox[1]
    draw.text((x - width / 2, y - height / 2), text, font=font, fill=fill)


def draw_waveform_panel(
    draw: Any,
    samples: Any,
    sample_rate: int,
    *,
    x: int,
    y: int,
    width: int,
    height: int,
    start_seconds: float,
    end_seconds: float,
    waveform_color: tuple[int, int, int, int],
    axis_color: tuple[int, int, int, int],
) -> None:
    import numpy as np

    start_sample = max(0, int(start_seconds * sample_rate))
    end_sample = min(len(samples), int(end_seconds * sample_rate))
    if end_sample <= start_sample:
        return
    panel = samples[start_sample:end_sample]
    center_y = y + height // 2
    draw.line((x, center_y, x + width, center_y), fill=axis_color, width=1)
    for pixel in range(width):
        a = int(pixel * len(panel) / width)
        b = int((pixel + 1) * len(panel) / width)
        segment = panel[a : max(a + 1, b)]
        low = float(np.min(segment))
        high = float(np.max(segment))
        y1 = center_y - round(high * height * 0.46)
        y2 = center_y - round(low * height * 0.46)
        draw.line((x + pixel, y1, x + pixel, y2), fill=waveform_color)


def draw_marker(
    draw: Any,
    *,
    time_seconds: float,
    start_seconds: float,
    end_seconds: float,
    x: int,
    y: int,
    width: int,
    height: int,
    color: tuple[int, int, int, int],
    label: str | None = None,
    font: Any | None = None,
) -> None:
    if not (start_seconds <= time_seconds <= end_seconds):
        return
    px = x + round((time_seconds - start_seconds) / (end_seconds - start_seconds) * width)
    draw.line((px, y, px, y + height), fill=color, width=1)
    if label and font:
        draw.text((px + 4, y + 3), label, font=font, fill=color)


def format_time(seconds: float) -> str:
    minutes = int(seconds // 60)
    secs = seconds - minutes * 60
    return f"{minutes:02d}:{secs:05.2f}"


def draw_time_ticks(
    draw: Any,
    *,
    start_seconds: float,
    end_seconds: float,
    x: int,
    y: int,
    width: int,
    interval_seconds: float,
    font: Any,
) -> None:
    tick = math.ceil(start_seconds / interval_seconds) * interval_seconds
    while tick <= end_seconds:
        px = x + round((tick - start_seconds) / (end_seconds - start_seconds) * width)
        draw.line((px, y, px, y + 8), fill=(120, 120, 138, 180), width=1)
        draw_centered(draw, (px, y + 24), format_time(tick), font, (145, 145, 160, 220))
        tick += interval_seconds


def write_waveform_audit(
    path: Path,
    samples: Any,
    sample_rate: int,
    duration: float,
    *,
    global_peaks: list[TransientPeak],
    final_peaks: list[TransientPeak],
    authored_pulses: list[AuthoredPulse],
    score_landmarks: list[ScoreLandmark],
    trigger_starts: dict[int, float],
) -> None:
    image_module, image_draw, image_font = load_pillow()
    width = 2400
    height = 1600
    image = image_module.new("RGBA", (width, height), (5, 6, 12, 255))
    draw = image_draw.Draw(image, "RGBA")
    title_font = load_font(image_font, 40, bold=True)
    label_font = load_font(image_font, 22, bold=True)
    small_font = load_font(image_font, 18)
    tiny_font = load_font(image_font, 15)

    draw.text((70, 40), "Flashlights in the Dark - waveform/transient alignment audit", font=title_font, fill=(238, 236, 248, 255))
    draw.text(
        (70, 92),
        "Cyan/yellow: reference audio transients. Orange: MusicXML note landmarks. Green: authored M115 light onsets. Red: Trigger 12 start.",
        font=small_font,
        fill=(178, 176, 194, 255),
    )

    panel_x = 90
    panel_width = width - 180
    panel_height = 170
    row_y = 150
    row_gap = 215
    rows = [
        (0.0, 110.0),
        (110.0, 220.0),
        (220.0, 330.0),
        (330.0, duration),
    ]
    for index, (start, end) in enumerate(rows):
        y = row_y + index * row_gap
        draw.text((panel_x, y - 28), f"{format_time(start)} - {format_time(end)}", font=label_font, fill=(212, 210, 228, 255))
        draw.rectangle((panel_x, y, panel_x + panel_width, y + panel_height), outline=(42, 44, 58, 255), width=1)
        draw_waveform_panel(
            draw,
            samples,
            sample_rate,
            x=panel_x,
            y=y,
            width=panel_width,
            height=panel_height,
            start_seconds=start,
            end_seconds=end,
            waveform_color=(125, 178, 255, 145),
            axis_color=(58, 60, 74, 180),
        )
        for peak in global_peaks:
            draw_marker(
                draw,
                time_seconds=peak.time,
                start_seconds=start,
                end_seconds=end,
                x=panel_x,
                y=y,
                width=panel_width,
                height=panel_height,
                color=(58, 236, 255, 72),
            )
        for peak in final_peaks:
            draw_marker(
                draw,
                time_seconds=peak.time,
                start_seconds=start,
                end_seconds=end,
                x=panel_x,
                y=y,
                width=panel_width,
                height=panel_height,
                color=(255, 213, 64, 170),
            )
        for pulse in authored_pulses:
            draw_marker(
                draw,
                time_seconds=pulse.time,
                start_seconds=start,
                end_seconds=end,
                x=panel_x,
                y=y,
                width=panel_width,
                height=panel_height,
                color=(96, 255, 166, 120),
            )
        for landmark in score_landmarks:
            draw_marker(
                draw,
                time_seconds=landmark.time,
                start_seconds=start,
                end_seconds=end,
                x=panel_x,
                y=y,
                width=panel_width,
                height=panel_height,
                color=(255, 154, 76, 55),
            )
        for event_id, start_time in sorted(trigger_starts.items()):
            draw_marker(
                draw,
                time_seconds=start_time,
                start_seconds=start,
                end_seconds=end,
                x=panel_x,
                y=y,
                width=panel_width,
                height=panel_height,
                color=(190, 190, 205, 120),
                label=f"T{event_id}" if event_id in {1, 2, 12} else None,
                font=tiny_font,
            )
        draw_time_ticks(
            draw,
            start_seconds=start,
            end_seconds=end,
            x=panel_x,
            y=y + panel_height + 6,
            width=panel_width,
            interval_seconds=30.0,
            font=tiny_font,
        )

    zoom_start = 300.0
    zoom_end = 430.0
    zoom_y = 1060
    zoom_height = 330
    draw.text((panel_x, zoom_y - 38), "Ending zoom: audio landmarks vs authored M115 light onsets", font=label_font, fill=(240, 238, 252, 255))
    draw.rectangle((panel_x, zoom_y, panel_x + panel_width, zoom_y + zoom_height), outline=(58, 60, 78, 255), width=1)
    draw_waveform_panel(
        draw,
        samples,
        sample_rate,
        x=panel_x,
        y=zoom_y,
        width=panel_width,
        height=zoom_height,
        start_seconds=zoom_start,
        end_seconds=zoom_end,
        waveform_color=(144, 190, 255, 170),
        axis_color=(58, 60, 74, 180),
    )
    for peak in final_peaks:
        draw_marker(
            draw,
            time_seconds=peak.time,
            start_seconds=zoom_start,
            end_seconds=zoom_end,
            x=panel_x,
            y=zoom_y,
            width=panel_width,
            height=zoom_height,
            color=(255, 213, 64, 210),
        )
    for pulse in authored_pulses:
        draw_marker(
            draw,
            time_seconds=pulse.time,
            start_seconds=zoom_start,
            end_seconds=zoom_end,
            x=panel_x,
            y=zoom_y,
            width=panel_width,
            height=zoom_height,
            color=(96, 255, 166, 165),
        )
    for landmark in score_landmarks:
        draw_marker(
            draw,
            time_seconds=landmark.time,
            start_seconds=zoom_start,
            end_seconds=zoom_end,
            x=panel_x,
            y=zoom_y,
            width=panel_width,
            height=zoom_height,
            color=(255, 154, 76, 85),
        )
    if 12 in trigger_starts:
        draw_marker(
            draw,
            time_seconds=trigger_starts[12],
            start_seconds=zoom_start,
            end_seconds=zoom_end,
            x=panel_x,
            y=zoom_y,
            width=panel_width,
            height=zoom_height,
            color=(255, 85, 95, 255),
            label="Trigger 12 authored start",
            font=small_font,
        )
    if authored_pulses:
        draw_marker(
            draw,
            time_seconds=authored_pulses[0].time,
            start_seconds=zoom_start,
            end_seconds=zoom_end,
            x=panel_x,
            y=zoom_y,
            width=panel_width,
            height=zoom_height,
            color=(95, 255, 168, 255),
            label="first authored light onset",
            font=small_font,
        )
    draw_time_ticks(
        draw,
        start_seconds=zoom_start,
        end_seconds=zoom_end,
        x=panel_x,
        y=zoom_y + zoom_height + 8,
        width=panel_width,
        interval_seconds=10.0,
        font=tiny_font,
    )

    if authored_pulses:
        summary = (
            f"Authored M115 light onsets: {len(authored_pulses)} group onsets, "
            f"{format_time(authored_pulses[0].time)} - {format_time(authored_pulses[-1].time)}"
        )
        draw.text((panel_x, 1480), summary, font=small_font, fill=(146, 255, 190, 255))
    path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(path, quality=95)


def make_base_frame(
    image_module: Any,
    image_draw: Any,
    image_font: Any,
    groups: list[StageGroup],
    width: int,
    height: int,
) -> Any:
    base = image_module.new("RGBA", (width, height), (3, 4, 8, 255))
    draw = image_draw.Draw(base, "RGBA")
    title_font = load_font(image_font, round(height * 0.048), bold=True)
    subtitle_font = load_font(image_font, round(height * 0.026))
    label_font = load_font(image_font, round(height * 0.032), bold=True)

    dot_y = round(height * 0.47)
    label_y = dot_y + round(height * 0.115)
    title_y = round(height * 0.16)

    draw_centered(
        draw,
        (width // 2, title_y),
        "Flashlights in the Dark - full light-show demo",
        title_font,
        (238, 236, 248, 255),
    )
    draw_centered(
        draw,
        (width // 2, title_y + round(height * 0.058)),
        "Six choir/stage groups rendered from twelve_trigger_light_show.json",
        subtitle_font,
        (172, 170, 188, 255),
    )

    dot_overlay = image_module.new("RGBA", (width, height), (0, 0, 0, 0))
    dot_draw = image_draw.Draw(dot_overlay, "RGBA")
    for group in groups:
        color = STAGE_COLORS[group.key]
        radius = round(height * 0.045)
        bbox = [group.x - radius, dot_y - radius, group.x + radius, dot_y + radius]
        dot_draw.ellipse(bbox, fill=(*color, 8), outline=(*color, 72), width=max(2, round(height * 0.004)))
    base = image_module.alpha_composite(base, dot_overlay)

    draw = image_draw.Draw(base, "RGBA")
    for group in groups:
        draw_centered(draw, (group.x, label_y), group.label, label_font, (205, 204, 220, 255))
    return base


def draw_dynamic_dots(
    image_module: Any,
    image_draw: Any,
    base: Any,
    groups: list[StageGroup],
    levels: dict[str, float],
    width: int,
    height: int,
    cue_label: str | None,
    time_seconds: float,
    cue_font: Any,
    time_font: Any,
) -> bytes:
    frame = base.copy()
    overlay = image_module.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = image_draw.Draw(overlay, "RGBA")

    dot_y = round(height * 0.47)
    for group in groups:
        level = levels[group.key]
        if level <= 0:
            continue
        color = STAGE_COLORS[group.key]
        perceptual = level**0.68
        halo_radius = round(height * (0.065 + 0.015 * perceptual))
        core_radius = round(height * (0.042 + 0.007 * perceptual))
        halo_alpha = max(0, min(150, round(118 * perceptual)))
        core_alpha = max(0, min(255, round(35 + 220 * perceptual)))
        halo_box = [
            group.x - halo_radius,
            dot_y - halo_radius,
            group.x + halo_radius,
            dot_y + halo_radius,
        ]
        core_box = [
            group.x - core_radius,
            dot_y - core_radius,
            group.x + core_radius,
            dot_y + core_radius,
        ]
        draw.ellipse(halo_box, fill=(*color, halo_alpha))
        draw.ellipse(core_box, fill=(*color, core_alpha))
        if level >= 0.85:
            spark_radius = max(2, round(height * 0.007))
            spark_box = [
                group.x - spark_radius,
                dot_y - spark_radius,
                group.x + spark_radius,
                dot_y + spark_radius,
            ]
            draw.ellipse(spark_box, fill=(255, 255, 255, round(95 * perceptual)))

    frame = image_module.alpha_composite(frame, overlay)
    draw = image_draw.Draw(frame, "RGBA")

    if cue_label:
        draw_centered(draw, (width // 2, round(height * 0.82)), cue_label, cue_font, (188, 186, 204, 255))
    timestamp = f"{math.floor(time_seconds // 60):02d}:{math.floor(time_seconds % 60):02d}"
    draw_centered(draw, (width // 2, round(height * 0.91)), timestamp, time_font, (120, 120, 138, 255))
    return frame.convert("RGB").tobytes()


def render_video(
    audio: Path,
    output: Path,
    light_show: dict[str, Any],
    starts: dict[int, float],
    duration: float,
    width: int,
    height: int,
    fps: int,
    stretch_final_event_to_audio_tail: bool,
    final_audio_peaks: list[TransientPeak] | None,
) -> None:
    image_module, image_draw, image_font = load_pillow()
    groups = build_groups(light_show["stageOrder"], width)
    timelines, cues, sync_notes = build_timelines(
        light_show,
        starts,
        groups,
        duration,
        stretch_final_event_to_audio_tail=stretch_final_event_to_audio_tail,
        final_audio_peaks=final_audio_peaks,
    )
    if "finalAudioPeakCount" in sync_notes:
        print(
            "Final event waveform sync: "
            f"{int(sync_notes['finalAudioPeakCount'])} attacks from "
            f"{sync_notes['finalAudioStartSeconds']:.3f}s to "
            f"{sync_notes['finalAudioEndSeconds']:.3f}s"
        )
    elif sync_notes:
        print(
            "Final event tail stretch: "
            f"{sync_notes['declaredFinalDurationSeconds']:.3f}s -> "
            f"{sync_notes['audioTailDurationSeconds']:.3f}s "
            f"(x{sync_notes['finalEventTimeScale']:.5f})"
        )
    base = make_base_frame(image_module, image_draw, image_font, groups, width, height)
    cue_font = load_font(image_font, round(height * 0.03))
    time_font = load_font(image_font, round(height * 0.026))

    total_frames = math.ceil(duration * fps)
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        "ffmpeg",
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb24",
        "-s",
        f"{width}x{height}",
        "-r",
        str(fps),
        "-i",
        "pipe:0",
        "-i",
        str(audio),
        "-map",
        "0:v:0",
        "-map",
        "1:a:0",
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-crf",
        "19",
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "aac",
        "-b:a",
        "192k",
        "-movflags",
        "+faststart",
        "-shortest",
        str(output),
    ]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    assert process.stdin is not None
    assert process.stderr is not None

    segment_indices = {group.key: 0 for group in groups}
    cue_index = 0
    try:
        for frame_index in range(total_frames):
            t = frame_index / fps
            levels: dict[str, float] = {}
            for group in groups:
                level, next_index = level_at_time(timelines[group.key], segment_indices[group.key], t)
                segment_indices[group.key] = next_index
                levels[group.key] = level
            cue_label, cue_index = cue_at_time(cues, cue_index, t)
            frame_bytes = draw_dynamic_dots(
                image_module,
                image_draw,
                base,
                groups,
                levels,
                width,
                height,
                cue_label,
                t,
                cue_font,
                time_font,
            )
            process.stdin.write(frame_bytes)
            if frame_index and frame_index % (fps * 30) == 0:
                print(f"Rendered {frame_index / fps:6.1f}s / {duration:6.1f}s", file=sys.stderr)
    finally:
        process.stdin.close()

    stderr = process.stderr.read().decode("utf-8", errors="replace")
    return_code = process.wait()
    if return_code != 0:
        raise RuntimeError(f"ffmpeg failed with exit code {return_code}\n{stderr}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audio", type=Path, default=DEFAULT_AUDIO)
    parser.add_argument("--light-show", type=Path, default=DEFAULT_LIGHT_SHOW)
    parser.add_argument("--timing-csv", type=Path, default=DEFAULT_TIMING_CSV)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--waveform-audit", type=Path, default=DEFAULT_WAVEFORM_AUDIT)
    parser.add_argument("--transient-csv", type=Path, default=DEFAULT_TRANSIENT_CSV)
    parser.add_argument("--score-analysis", type=Path, default=DEFAULT_SCORE_ANALYSIS)
    parser.add_argument("--audit-only", action="store_true")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--fps", type=int, default=24)
    parser.add_argument("--analysis-sample-rate", type=int, default=24000)
    parser.add_argument("--global-transient-percentile", type=float, default=90.0)
    parser.add_argument("--final-transient-percentile", type=float, default=80.0)
    parser.add_argument("--final-transient-start", type=float, default=315.0)
    parser.add_argument("--final-transient-end", type=float, default=430.0)
    parser.add_argument(
        "--enable-final-transient-sync",
        action="store_true",
        help=(
            "Experimental: replace the final M115 light show with detected audio "
            "transient pulses. Disabled by default because the authored show is "
            "the performance source of truth."
        ),
    )
    parser.add_argument(
        "--stretch-final-event-to-audio-tail",
        action="store_true",
        dest="stretch_final_event_to_audio_tail",
        help=(
            "Experimental: scale the final M115 light keyframes to the actual "
            "remaining soundtrack duration. Disabled by default because the "
            "runtime client plays the authored timing."
        ),
    )
    args = parser.parse_args()

    audio = args.audio.resolve()
    light_show_path = args.light_show.resolve()
    timing_csv = args.timing_csv.resolve()
    output = args.output.resolve()
    waveform_audit = args.waveform_audit.resolve()
    transient_csv = args.transient_csv.resolve()
    score_analysis = args.score_analysis.resolve()

    duration = audio_duration_seconds(audio)
    light_show = load_light_show(light_show_path)
    starts = load_trigger_starts(timing_csv)
    authored_final_pulses = collect_authored_pulses(light_show, starts, event_id=12)
    score_landmarks = load_score_landmarks(score_analysis, starts)
    samples = decode_audio_mono(audio, args.analysis_sample_rate)
    flux_times, flux = compute_onset_flux(samples, args.analysis_sample_rate)
    global_peaks = detect_peaks(
        flux_times,
        flux,
        percentile=args.global_transient_percentile,
        min_distance_seconds=0.35,
        source="full_piece",
    )
    final_peaks = detect_peaks(
        flux_times,
        flux,
        percentile=args.final_transient_percentile,
        min_distance_seconds=0.65,
        start_seconds=args.final_transient_start,
        end_seconds=args.final_transient_end,
        threshold_scope="window",
        source="final_who_are_we",
    )
    if args.enable_final_transient_sync:
        video_final_peaks = final_peaks
        args.stretch_final_event_to_audio_tail = False
    else:
        video_final_peaks = None
    write_transient_csv(transient_csv, global_peaks, final_peaks)
    write_waveform_audit(
        waveform_audit,
        samples,
        args.analysis_sample_rate,
        duration,
        global_peaks=global_peaks,
        final_peaks=final_peaks,
        authored_pulses=authored_final_pulses,
        score_landmarks=score_landmarks,
        trigger_starts=starts,
    )
    if args.audit_only:
        print(f"Waveform audit: {waveform_audit}")
        print(f"Transient CSV: {transient_csv}")
        print(f"Score landmarks: {len(score_landmarks)} from {score_analysis}")
        if final_peaks:
            print(
                f"Reference final transients: {len(final_peaks)} "
                f"({final_peaks[0].time:.3f}s to {final_peaks[-1].time:.3f}s)"
            )
        if authored_final_pulses:
            print(
                f"Authored final light onsets: {len(authored_final_pulses)} "
                f"({authored_final_pulses[0].time:.3f}s to {authored_final_pulses[-1].time:.3f}s)"
            )
        return
    render_video(
        audio,
        output,
        light_show,
        starts,
        duration,
        args.width,
        args.height,
        args.fps,
        args.stretch_final_event_to_audio_tail,
        video_final_peaks,
    )
    print(f"Rendered {output}")
    print(f"Duration source: {duration:.3f}s")
    print(f"Frame rate: {args.fps} fps")
    print(f"Waveform audit: {waveform_audit}")
    print(f"Transient CSV: {transient_csv}")
    print(f"Score landmarks: {len(score_landmarks)} from {score_analysis}")
    if final_peaks:
        print(
            f"Reference final transients: {len(final_peaks)} "
            f"({final_peaks[0].time:.3f}s to {final_peaks[-1].time:.3f}s)"
        )
    if authored_final_pulses:
        print(
            f"Authored final light onsets: {len(authored_final_pulses)} "
            f"({authored_final_pulses[0].time:.3f}s to {authored_final_pulses[-1].time:.3f}s)"
        )


if __name__ == "__main__":
    main()
