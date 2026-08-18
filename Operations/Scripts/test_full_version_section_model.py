#!/usr/bin/env python3

from __future__ import annotations

import json
import unittest

from build_full_version_section_model import SCHEMA_PATH, build_section_model


class FullVersionSectionModelTests(unittest.TestCase):
    def setUp(self) -> None:
        self.updated = build_section_model(json.loads(SCHEMA_PATH.read_text()))

    def test_retains_twelve_operator_triggers_and_adds_eighteen_sections(self) -> None:
        self.assertEqual(12, self.updated["operatorTriggerCount"])
        self.assertEqual(12, len(self.updated["events"]))
        self.assertEqual(18, self.updated["visualSectionCount"])
        self.assertEqual(18, len(self.updated["visualSections"]))

    def test_sections_cover_the_timeline_without_gaps(self) -> None:
        sections = self.updated["visualSections"]
        self.assertEqual(0.0, sections[0]["startAtMs"])
        for previous, current in zip(sections, sections[1:]):
            self.assertEqual(previous["endAtMs"], current["startAtMs"])
        self.assertGreater(sections[-1]["endAtMs"], 0.0)

    def test_each_trigger_window_is_partitioned_by_sections(self) -> None:
        for event in self.updated["events"]:
            windows = event["visualSectionWindows"]
            self.assertTrue(windows)
            self.assertEqual(0.0, windows[0]["startAtMs"])
            for previous, current in zip(windows, windows[1:]):
                self.assertEqual(previous["endAtMs"], current["startAtMs"])
            self.assertAlmostEqual(float(event["availableWindowMs"]), windows[-1]["endAtMs"], places=2)

    def test_expected_late_form_boundaries_are_present(self) -> None:
        starts = {section["startMeasure"] for section in self.updated["visualSections"]}
        self.assertTrue({112, 115, 130, 140}.issubset(starts))


if __name__ == "__main__":
    unittest.main()
