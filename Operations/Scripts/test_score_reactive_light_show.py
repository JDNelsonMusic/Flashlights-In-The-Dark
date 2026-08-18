#!/usr/bin/env python3
"""Tests for the score-reactive light-show generator."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from score_reactive_light_show import (
    build_score_light_analysis,
    build_score_reactive_manifest,
    load_json,
)


ROOT = Path(__file__).resolve().parents[2]
SCORE_PATH = ROOT / "Engraving/Scores/FlashlightsInTheDark_v26_NewerScoreWithFewerParts.musicxml"
TRIGGER_MANIFEST_PATH = ROOT / "DAW-Production/Audits/electronics_trigger_assets.json"
BASELINE_LIGHT_SHOW_PATH = ROOT / "Engraving/Score-Study/twelve_trigger_light_show.json"
GRAMMAR_PATH = ROOT / "Engraving/Score-Study/score_reactive_light_grammar_full_version.json"


class ScoreReactiveLightShowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.analysis = build_score_light_analysis(
            score_path=SCORE_PATH,
            trigger_manifest_path=TRIGGER_MANIFEST_PATH,
            baseline_light_show_path=BASELINE_LIGHT_SHOW_PATH,
        )
        cls.baseline = load_json(BASELINE_LIGHT_SHOW_PATH)
        cls.grammar = load_json(GRAMMAR_PATH)
        cls.manifest = build_score_reactive_manifest(
            baseline_light_show=cls.baseline,
            analysis=cls.analysis,
            grammar=cls.grammar,
            analysis_path=Path("Engraving/Score-Study/score_light_analysis_full_version.json"),
            grammar_path=Path("Engraving/Score-Study/score_reactive_light_grammar_full_version.json"),
        )

    def test_extracts_tempo_and_trigger_activity(self) -> None:
        tempos = [round(item["bpm"]) for item in self.analysis["tempoMap"]]
        self.assertIn(102, tempos)
        self.assertIn(72, tempos)
        self.assertEqual(len(self.analysis["triggers"]), 12)
        by_id = {item["id"]: item for item in self.analysis["triggers"]}
        self.assertGreater(by_id[12]["noteCount"], 100)
        self.assertGreater(by_id[10]["densityPerSecond"], 0)

    def test_generated_manifest_shape_and_keyframes(self) -> None:
        self.assertEqual(len(self.manifest["events"]), 12)
        for event in self.manifest["events"]:
            self.assertEqual(set(event["parts"].keys()), set(self.manifest["stageOrder"][i]["key"] for i in range(6)))
            for part in event["parts"].values():
                previous_at = -1.0
                self.assertGreaterEqual(len(part["keyframes"]), 2)
                for keyframe in part["keyframes"]:
                    at_ms = float(keyframe["atMs"])
                    level = float(keyframe["level"])
                    self.assertGreaterEqual(at_ms, previous_at)
                    self.assertGreaterEqual(level, 0.0)
                    self.assertLessEqual(level, 1.0)
                    if "interpolation" in keyframe:
                        self.assertIn(keyframe["interpolation"], {"linear", "step"})
                    previous_at = at_ms
                self.assertEqual(float(part["keyframes"][-1]["level"]), 0.0)

    def test_trigger_twelve_is_preserved(self) -> None:
        baseline_twelve = next(event for event in self.baseline["events"] if int(event["id"]) == 12)
        generated_twelve = next(event for event in self.manifest["events"] if int(event["id"]) == 12)
        self.assertEqual(
            json.dumps(baseline_twelve["parts"], sort_keys=True),
            json.dumps(generated_twelve["parts"], sort_keys=True),
        )


if __name__ == "__main__":
    unittest.main()
