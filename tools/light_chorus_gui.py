"""Entry point for the Flashlights Light Chorus desktop app."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from light_chorus_app.gui import run_app


if __name__ == "__main__":
    run_app()
