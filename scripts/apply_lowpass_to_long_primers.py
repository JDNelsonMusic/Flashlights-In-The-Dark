#!/usr/bin/env python3

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
TARGET_DIRS = (
    ROOT / "flashlights_client" / "available-sounds" / "primerTones",
    ROOT / "FlashlightsInTheDark_MacOS" / "Audio" / "primerTones",
)

FFMPEG_FILTER = "lowpass=f=3000:p=2"
EXPECTED_FILE_NAMES = tuple(f"Long{number}.mp3" for number in range(50, 99))


def ensure_ffmpeg() -> None:
    if shutil.which("ffmpeg") is None:
        raise SystemExit("ffmpeg is required but was not found in PATH")


def verify_targets() -> None:
    for directory in TARGET_DIRS:
        if not directory.is_dir():
            raise SystemExit(f"Missing primer tone directory: {directory}")
        present = tuple(path.name for path in sorted(directory.glob("Long*.mp3")))
        if present != EXPECTED_FILE_NAMES:
            raise SystemExit(
                f"Unexpected long-primer set in {directory}: "
                f"found {len(present)} files"
            )


def filter_file(path: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="long-primer-lowpass-") as tmp_dir:
        temp_output = Path(tmp_dir) / path.name
        command = [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(path),
            "-af",
            FFMPEG_FILTER,
            "-codec:a",
            "libmp3lame",
            "-b:a",
            "192k",
            str(temp_output),
        ]
        subprocess.run(command, check=True)
        temp_output.replace(path)


def main() -> int:
    ensure_ffmpeg()
    verify_targets()

    for directory in TARGET_DIRS:
        for file_name in EXPECTED_FILE_NAMES:
            filter_file(directory / file_name)
        print(f"Filtered 49 long primer tones in {directory}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
