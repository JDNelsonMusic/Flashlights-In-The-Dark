"""Entry point for the Flashlights Light Chorus desktop app."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from Operations/Light-Chorus.gui import run_app


if __name__ == "__main__":
    run_app()
