#!/usr/bin/env python3

from __future__ import annotations

import argparse
import pathlib
import re
import sys


VERSION_RE = re.compile(r"^(version:\s*)(\d+\.\d+\.\d+)\+(\d+)(\s*)$", re.MULTILINE)
BUILD_NAME_RE = re.compile(r"^(FLUTTER_BUILD_NAME=).*$", re.MULTILINE)
BUILD_NUMBER_RE = re.compile(r"^(FLUTTER_BUILD_NUMBER=).*$", re.MULTILINE)


def bump_pubspec(pubspec_path: pathlib.Path) -> tuple[str, int]:
    original = pubspec_path.read_text(encoding="utf-8")
    match = VERSION_RE.search(original)
    if match is None:
        raise ValueError(f"Could not find Flutter version in {pubspec_path}")

    version_name = match.group(2)
    build_number = int(match.group(3)) + 1
    updated = VERSION_RE.sub(
        rf"\g<1>{version_name}+{build_number}\g<4>",
        original,
        count=1,
    )
    pubspec_path.write_text(updated, encoding="utf-8")
    return version_name, build_number


def sync_generated_xcconfig(
    generated_xcconfig_path: pathlib.Path,
    version_name: str,
    build_number: int,
) -> None:
    if not generated_xcconfig_path.exists():
        return

    original = generated_xcconfig_path.read_text(encoding="utf-8")
    updated = BUILD_NAME_RE.sub(rf"\g<1>{version_name}", original)
    updated = BUILD_NUMBER_RE.sub(rf"\g<1>{build_number}", updated)
    generated_xcconfig_path.write_text(updated, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pubspec", required=True)
    parser.add_argument("--generated-xcconfig", required=True)
    args = parser.parse_args()

    pubspec_path = pathlib.Path(args.pubspec).resolve()
    generated_xcconfig_path = pathlib.Path(args.generated_xcconfig).resolve()

    version_name, build_number = bump_pubspec(pubspec_path)
    sync_generated_xcconfig(generated_xcconfig_path, version_name, build_number)

    print(
        f"[ios-version] Bumped Flutter archive version to {version_name}+{build_number}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
