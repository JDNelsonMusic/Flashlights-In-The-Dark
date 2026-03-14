#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SESSION_DIR = ROOT / "FlashlightsInTheDark_Protools-Session"
DEFAULT_OUTPUT_DIR = ROOT / "docs" / "protools-housekeeping"
FFPROBE_CMD = [
    "ffprobe",
    "-v",
    "error",
    "-show_entries",
    "stream=codec_name,sample_rate,channels:format=duration,bit_rate",
    "-of",
    "json",
]
ZERO_DIR_NAMES = {
    "Bounced Files",
    "Clip Groups",
    "Rendered Files",
    "untitled folder",
}
BACKUP_SUFFIX_RE = re.compile(r"\.bak\.(\d+)$")
RECOVERED_SUFFIX_RE = re.compile(r"\.recovered[\w.-]*")
CHANNEL_SUFFIX_RE = re.compile(r"\.(L|R)$", re.IGNORECASE)
ITERATION_SUFFIX_RE = re.compile(r" \(\d+\)$")
TIMESHIFT_SUFFIX_RE = re.compile(r"-TmShft_[\d-]+$")
WEIRD_NAME_RE = re.compile(r"[!]")
DOUBLE_SPACE_RE = re.compile(r"  +")
TOP_LEVEL_SESSION_HINTS = ("FlashlightsInTheDark", "MappingPrimerTones", "CleanedMIDI")


def isoformat_timestamp(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat(timespec="seconds")


def human_size(num_bytes: int) -> str:
    suffixes = ["B", "KB", "MB", "GB", "TB"]
    size = float(num_bytes)
    for suffix in suffixes:
        if size < 1024 or suffix == suffixes[-1]:
            if suffix == "B":
                return f"{int(size)} {suffix}"
            return f"{size:.1f} {suffix}"
        size /= 1024
    return f"{num_bytes} B"


def path_size(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    return sum(child.stat().st_size for child in path.rglob("*") if child.is_file())


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_lineage(name: str) -> str:
    stem = name
    if stem.endswith(".ptx"):
        stem = stem[:-4]
    match = BACKUP_SUFFIX_RE.search(stem)
    if match:
        stem = stem[: match.start()]
    while True:
        next_stem = RECOVERED_SUFFIX_RE.sub("", stem)
        if next_stem == stem:
            break
        stem = next_stem
    if stem.endswith(".r"):
        stem = stem[:-2]
    return stem


def normalize_audio_family(name: str) -> str:
    stem = Path(name).stem
    stem = CHANNEL_SUFFIX_RE.sub("", stem)
    stem = ITERATION_SUFFIX_RE.sub("", stem)
    stem = TIMESHIFT_SUFFIX_RE.sub("", stem)
    stem = DOUBLE_SPACE_RE.sub(" ", stem).strip()
    return stem


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


def build_session_entries(session_dir: Path) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for path in sorted(session_dir.glob("*.ptx")):
        stat = path.stat()
        lineage = normalize_lineage(path.name)
        name_lower = path.name.lower()
        entries.append(
            {
                "name": path.name,
                "path": str(path.relative_to(ROOT)),
                "lineage": lineage,
                "size_bytes": stat.st_size,
                "mtime_utc": isoformat_timestamp(stat.st_mtime),
                "contains_project_name": "flashlightsinthedark" in name_lower,
                "contains_mapping_primer_tones": "mappingprimertones" in name_lower,
                "contains_cleaned_midi": "cleanedmidi" in name_lower,
                "looks_scratch": "flashlightsinthedark" not in name_lower,
            }
        )
    return entries


def build_backup_entries(session_dir: Path) -> list[dict[str, Any]]:
    backup_dir = session_dir / "Session File Backups"
    entries: list[dict[str, Any]] = []
    if not backup_dir.exists():
        return entries

    for path in sorted(backup_dir.glob("*.ptx")):
        stat = path.stat()
        match = BACKUP_SUFFIX_RE.search(path.stem)
        backup_index = int(match.group(1)) if match else None
        entries.append(
            {
                "name": path.name,
                "path": str(path.relative_to(ROOT)),
                "lineage": normalize_lineage(path.name),
                "backup_index": backup_index,
                "size_bytes": stat.st_size,
                "mtime_utc": isoformat_timestamp(stat.st_mtime),
                "is_recovered": ".recovered" in path.name,
            }
        )
    return entries


def build_lineage_summary(
    sessions: list[dict[str, Any]],
    backups: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, Any]] = {}

    for session in sessions:
        summary = grouped.setdefault(
            session["lineage"],
            {
                "lineage": session["lineage"],
                "top_level_sessions": [],
                "backups": [],
            },
        )
        summary["top_level_sessions"].append(session)

    for backup in backups:
        summary = grouped.setdefault(
            backup["lineage"],
            {
                "lineage": backup["lineage"],
                "top_level_sessions": [],
                "backups": [],
            },
        )
        summary["backups"].append(backup)

    summaries: list[dict[str, Any]] = []
    for lineage, summary in grouped.items():
        top_level_sessions = summary["top_level_sessions"]
        backup_entries = summary["backups"]
        top_level_sessions.sort(key=lambda item: item["mtime_utc"])
        backup_entries.sort(key=lambda item: item["mtime_utc"])
        summaries.append(
            {
                "lineage": lineage,
                "top_level_count": len(top_level_sessions),
                "backup_count": len(backup_entries),
                "latest_top_level_session": top_level_sessions[-1]["path"] if top_level_sessions else None,
                "latest_top_level_mtime_utc": top_level_sessions[-1]["mtime_utc"] if top_level_sessions else None,
                "latest_backup_mtime_utc": backup_entries[-1]["mtime_utc"] if backup_entries else None,
                "contains_recovered_backups": any(entry["is_recovered"] for entry in backup_entries),
            }
        )

    summaries.sort(
        key=lambda item: (
            item["latest_top_level_mtime_utc"] or "",
            item["latest_backup_mtime_utc"] or "",
            item["lineage"],
        ),
        reverse=True,
    )
    return summaries


def rank_session_candidates(
    sessions: list[dict[str, Any]],
    lineage_summary: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    lineage_lookup = {item["lineage"]: item for item in lineage_summary}

    def sort_key(session: dict[str, Any]) -> tuple[Any, ...]:
        lineage = lineage_lookup.get(session["lineage"], {})
        return (
            1 if session["contains_project_name"] else 0,
            1 if session["contains_mapping_primer_tones"] else 0,
            1 if session["contains_cleaned_midi"] else 0,
            0 if session["looks_scratch"] else 1,
            lineage.get("latest_backup_mtime_utc") or "",
            session["mtime_utc"],
            session["size_bytes"],
        )

    ranked = []
    for session in sorted(sessions, key=sort_key, reverse=True):
        lineage = lineage_lookup.get(session["lineage"], {})
        reasons = []
        if session["contains_project_name"]:
            reasons.append("matches project naming")
        if session["contains_mapping_primer_tones"]:
            reasons.append("contains MappingPrimerTones workflow")
        if session["contains_cleaned_midi"]:
            reasons.append("contains CleanedMIDI workflow")
        if lineage.get("latest_backup_mtime_utc"):
            reasons.append("has matching backup lineage activity")
        ranked.append(
            {
                **session,
                "backup_count": lineage.get("backup_count", 0),
                "latest_backup_mtime_utc": lineage.get("latest_backup_mtime_utc"),
                "reasons": reasons,
            }
        )
    return ranked


def build_audio_inventory(session_dir: Path) -> list[dict[str, Any]]:
    inventory: list[dict[str, Any]] = []
    media_roots = [
        session_dir / "Audio Files",
        session_dir / "LongPrimers",
    ]
    for media_root in media_roots:
        if not media_root.exists():
            continue
        for path in sorted(media_root.rglob("*")):
            if not path.is_file():
                continue
            if path.suffix.lower() not in {".wav", ".mp3"}:
                continue
            stat = path.stat()
            entry = {
                "name": path.name,
                "path": str(path.relative_to(ROOT)),
                "root": media_root.name,
                "size_bytes": stat.st_size,
                "mtime_utc": isoformat_timestamp(stat.st_mtime),
                "extension": path.suffix.lower().lstrip("."),
                "family": normalize_audio_family(path.name),
            }
            entry.update(ffprobe_metadata(path))
            inventory.append(entry)
    return inventory


def find_exact_duplicate_audio(audio_inventory: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_size: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for entry in audio_inventory:
        by_size[entry["size_bytes"]].append(entry)

    duplicates: list[dict[str, Any]] = []
    for size_bytes, group in sorted(by_size.items()):
        if len(group) < 2:
            continue
        by_hash: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for entry in group:
            file_hash = sha256_file(ROOT / entry["path"])
            by_hash[file_hash].append(entry)
        for file_hash, hash_group in by_hash.items():
            if len(hash_group) < 2:
                continue
            duplicates.append(
                {
                    "sha256": file_hash,
                    "size_bytes": size_bytes,
                    "paths": [item["path"] for item in hash_group],
                }
            )
    return duplicates


def find_audio_variant_families(audio_inventory: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for entry in audio_inventory:
        grouped[entry["family"]].append(entry)

    families: list[dict[str, Any]] = []
    for family, group in grouped.items():
        names = [item["name"] for item in group]
        interesting = (
            len(group) > 2
            or any("(1)" in name for name in names)
            or any("-TmShft_" in name for name in names)
            or any("  " in name for name in names)
        )
        if not interesting:
            continue
        families.append(
            {
                "family": family,
                "count": len(group),
                "paths": [item["path"] for item in sorted(group, key=lambda item: item["path"])],
            }
        )
    families.sort(key=lambda item: (-item["count"], item["family"]))
    return families


def find_risky_filenames(session_dir: Path, audio_inventory: list[dict[str, Any]]) -> list[dict[str, Any]]:
    risky: list[dict[str, Any]] = []

    for path in sorted(session_dir.rglob("*")):
        if not path.is_file():
            continue
        flags = []
        name = path.name
        if name == ".DS_Store":
            flags.append("ds_store")
        if len(name) > 80:
            flags.append("long_name")
        if DOUBLE_SPACE_RE.search(name):
            flags.append("double_space")
        if WEIRD_NAME_RE.search(name):
            flags.append("punctuation")
        if " .L.wav" in name or " .R.wav" in name:
            flags.append("trailing_punctuation_before_channel")
        if "(1)" in name:
            flags.append("duplicate_iteration_suffix")
        if flags:
            risky.append(
                {
                    "path": str(path.relative_to(ROOT)),
                    "flags": flags,
                }
            )

    risky.sort(key=lambda item: (item["path"]))
    return risky


def build_cleanup_candidates(
    session_dir: Path,
    sessions: list[dict[str, Any]],
    duplicates: list[dict[str, Any]],
    risky_filenames: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []

    for path in sorted(session_dir.rglob(".DS_Store")):
        candidates.append(
            {
                "action": "delete",
                "risk": "low",
                "path": str(path.relative_to(ROOT)),
                "reason": "Finder metadata file; not part of Pro Tools content.",
            }
        )

    for path in sorted(session_dir.iterdir()):
        if path.is_dir() and path.name in ZERO_DIR_NAMES and path_size(path) == 0:
            candidates.append(
                {
                    "action": "delete_or_ignore",
                    "risk": "low",
                    "path": str(path.relative_to(ROOT)),
                    "reason": "Empty session subdirectory.",
                }
            )

    for session in sessions:
        if session["looks_scratch"]:
            candidates.append(
                {
                    "action": "manual_review",
                    "risk": "medium",
                    "path": session["path"],
                    "reason": "Top-level session file does not follow the project naming convention.",
                }
            )

    for duplicate in duplicates:
        if len(duplicate["paths"]) < 2:
            continue
        candidates.append(
            {
                "action": "manual_review",
                "risk": "medium",
                "path": duplicate["paths"][0],
                "reason": f"Exact duplicate audio exists in {len(duplicate['paths'])} files; dedupe only after validating PTX references.",
                "related_paths": duplicate["paths"][1:],
            }
        )

    for item in risky_filenames:
        flags = set(item["flags"])
        if flags == {"ds_store"}:
            continue
        candidates.append(
            {
                "action": "rename_or_rebucket",
                "risk": "medium",
                "path": item["path"],
                "reason": f"Filename flags: {', '.join(sorted(flags))}.",
            }
        )

    # Preserve input order by path/action to keep the report stable.
    candidates.sort(key=lambda item: (item["risk"], item["action"], item["path"]))
    return candidates


def markdown_list(items: list[str]) -> list[str]:
    if not items:
        return ["- none"]
    return [f"- {item}" for item in items]


def render_markdown(report: dict[str, Any]) -> str:
    lines: list[str] = []
    summary = report["summary"]

    lines.append("# Pro Tools Session Audit")
    lines.append("")
    lines.append(f"Generated: `{report['generated_utc']}`")
    lines.append(f"Session root: `{report['session_root']}`")
    lines.append("")
    lines.append("## Snapshot")
    lines.append("")
    lines.append(f"- Top-level `.ptx` sessions: `{summary['top_level_session_count']}`")
    lines.append(f"- Backup `.ptx` sessions: `{summary['backup_session_count']}`")
    lines.append(f"- Audio files inventoried: `{summary['audio_file_count']}`")
    lines.append(f"- Total session size: `{summary['session_size_human']}`")
    lines.append(f"- Recommended working session: `{report['recommended_working_session']['path'] if report['recommended_working_session'] else 'none'}`")
    lines.append("")

    lines.append("## Recommended Working Session")
    lines.append("")
    if report["recommended_working_session"]:
        candidate = report["recommended_working_session"]
        lines.append(f"- Path: `{candidate['path']}`")
        lines.append(f"- Modified: `{candidate['mtime_utc']}`")
        lines.append(f"- Size: `{human_size(candidate['size_bytes'])}`")
        lines.extend(markdown_list([f"Reason: {reason}" for reason in candidate["reasons"]]))
    else:
        lines.append("- none")
    lines.append("")

    lines.append("## Session Lineages")
    lines.append("")
    for lineage in report["lineages"][:12]:
        lines.append(
            f"- `{lineage['lineage']}`: top-level `{lineage['top_level_count']}`, backups `{lineage['backup_count']}`, latest top-level `{lineage['latest_top_level_mtime_utc']}`, latest backup `{lineage['latest_backup_mtime_utc']}`"
        )
    lines.append("")

    lines.append("## Audio Inventory")
    lines.append("")
    root_counts = report["audio_summary"]["by_root"]
    for root_name, count in sorted(root_counts.items()):
        lines.append(f"- `{root_name}`: `{count}` files")
    lines.append(f"- Extensions: `{report['audio_summary']['extensions']}`")
    lines.append(f"- Sample rates: `{report['audio_summary']['sample_rates']}`")
    lines.append(f"- Channel counts: `{report['audio_summary']['channels']}`")
    lines.append("")

    lines.append("## Exact Duplicate Audio")
    lines.append("")
    if report["exact_duplicate_audio"]:
        for duplicate in report["exact_duplicate_audio"]:
            lines.append(
                f"- `{human_size(duplicate['size_bytes'])}` duplicate set: {', '.join(f'`{path}`' for path in duplicate['paths'])}"
            )
    else:
        lines.append("- none detected")
    lines.append("")

    lines.append("## Variant Families")
    lines.append("")
    if report["audio_variant_families"]:
        for family in report["audio_variant_families"][:20]:
            lines.append(
                f"- `{family['family']}`: `{family['count']}` related files"
            )
    else:
        lines.append("- none flagged")
    lines.append("")

    lines.append("## Cleanup Candidates")
    lines.append("")
    if report["cleanup_candidates"]:
        for candidate in report["cleanup_candidates"][:40]:
            lines.append(
                f"- `{candidate['action']}` `{candidate['path']}` ({candidate['risk']} risk): {candidate['reason']}"
            )
    else:
        lines.append("- none")
    lines.append("")

    lines.append("## Notes")
    lines.append("")
    lines.extend(markdown_list(report["notes"]))
    lines.append("")
    return "\n".join(lines)


def build_report(session_dir: Path) -> dict[str, Any]:
    sessions = build_session_entries(session_dir)
    backups = build_backup_entries(session_dir)
    lineages = build_lineage_summary(sessions, backups)
    ranked_sessions = rank_session_candidates(sessions, lineages)
    audio_inventory = build_audio_inventory(session_dir)
    exact_duplicates = find_exact_duplicate_audio(audio_inventory)
    variant_families = find_audio_variant_families(audio_inventory)
    risky_filenames = find_risky_filenames(session_dir, audio_inventory)
    cleanup_candidates = build_cleanup_candidates(
        session_dir=session_dir,
        sessions=sessions,
        duplicates=exact_duplicates,
        risky_filenames=risky_filenames,
    )

    session_size = path_size(session_dir)
    audio_summary = {
        "by_root": dict(Counter(item["root"] for item in audio_inventory)),
        "extensions": dict(Counter(item["extension"] for item in audio_inventory)),
        "sample_rates": dict(
            Counter(str(item.get("sample_rate", "unknown")) for item in audio_inventory)
        ),
        "channels": dict(
            Counter(str(item.get("channels", "unknown")) for item in audio_inventory)
        ),
    }

    notes = [
        "The top-level session recommendation is heuristic. Confirm it in Pro Tools before deleting or renaming anything.",
        "Exact duplicate audio groups are safe to inspect, but not safe to delete automatically because PTX references are not parsed here.",
        "Files with long or irregular names should be normalized only after the canonical working session is confirmed.",
    ]

    return {
        "generated_utc": datetime.now(tz=timezone.utc).isoformat(timespec="seconds"),
        "session_root": str(session_dir.relative_to(ROOT)),
        "summary": {
            "top_level_session_count": len(sessions),
            "backup_session_count": len(backups),
            "audio_file_count": len(audio_inventory),
            "session_size_bytes": session_size,
            "session_size_human": human_size(session_size),
        },
        "recommended_working_session": ranked_sessions[0] if ranked_sessions else None,
        "top_level_sessions": sessions,
        "backups": backups,
        "lineages": lineages,
        "audio_inventory": audio_inventory,
        "audio_summary": audio_summary,
        "exact_duplicate_audio": exact_duplicates,
        "audio_variant_families": variant_families,
        "risky_filenames": risky_filenames,
        "cleanup_candidates": cleanup_candidates,
        "notes": notes,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit the Flashlights In The Dark Pro Tools session folder.")
    parser.add_argument(
        "--session-dir",
        type=Path,
        default=DEFAULT_SESSION_DIR,
        help="Path to the Pro Tools session root.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Directory where the generated report files should be written.",
    )
    args = parser.parse_args()

    session_dir = args.session_dir.resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    report = build_report(session_dir)
    json_path = output_dir / "session_audit.json"
    md_path = output_dir / "session_audit.md"

    json_path.write_text(json.dumps(report, indent=2) + "\n")
    md_path.write_text(render_markdown(report) + "\n")

    print(f"Wrote {json_path.relative_to(ROOT)}")
    print(f"Wrote {md_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
