#!/usr/bin/env python3
"""Focused negative test for the first-divergence comparator."""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts/run_differential.py"
SPEC = importlib.util.spec_from_file_location("run_differential", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {MODULE_PATH}")
DIFF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DIFF)


class ComparatorNegativeTest(unittest.TestCase):
    def test_modified_retire_trace_reports_first_divergence(self) -> None:
        reference = [
            {
                "kind": "retire",
                "order": 0,
                "pc": "0x80000000",
                "insn": "0x00700093",
                "rd_we": True,
                "rd_addr": 1,
                "rd_data": "0x00000007",
            },
            {
                "kind": "retire",
                "order": 1,
                "pc": "0x80000004",
                "insn": "0x00900113",
                "rd_we": True,
                "rd_addr": 2,
                "rd_data": "0x00000009",
            },
        ]

        with tempfile.TemporaryDirectory(prefix="rv32-comparator-negative.") as tmp:
            trace_path = Path(tmp) / "dut.modified.jsonl"
            modified = [dict(event) for event in reference]
            modified[1]["rd_data"] = "0xdeadbeef"
            trace_lines = modified + [
                {
                    "kind": "summary",
                    "status": "pass",
                    "cycles": 10,
                    "retires": 2,
                    "traps": 0,
                    "tohost": "0x00000001",
                }
            ]
            trace_path.write_text(
                "".join(json.dumps(event) + "\n" for event in trace_lines),
                encoding="utf-8",
            )

            dut_arch, _dut_memory, _summary = DIFF.read_dut_trace(trace_path)
            self.assertIsNone(DIFF.compare_stream("architecture", reference, reference))

            divergence = DIFF.compare_stream(
                "architecture", reference, dut_arch
            )
            self.assertIsNotNone(divergence)
            assert divergence is not None
            self.assertEqual(divergence["index"], 1)
            self.assertIn("rd_data differs", divergence["reason"])
            self.assertEqual(divergence["spike"]["rd_data"], "0x00000009")
            self.assertEqual(divergence["dut"]["rd_data"], "0xdeadbeef")

            artifact = Path(tmp) / "first_divergence.json"
            artifact.write_text(
                json.dumps(divergence, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            round_trip = json.loads(artifact.read_text(encoding="utf-8"))
            self.assertEqual(round_trip["stream"], "architecture")
            self.assertEqual(round_trip["index"], 1)

    def test_trap_free_profile_rejects_every_trap_source(self) -> None:
        retire = {
            "kind": "retire",
            "pc": "0x80000000",
            "insn": "0x00000013",
            "rd_we": False,
        }
        trap = {
            "kind": "trap",
            "pc": "0x80000004",
            "cause": "0x00000002",
            "value": "0xffffffff",
        }
        clean_summary = {"kind": "summary", "status": "pass", "traps": 0}

        self.assertIsNone(
            DIFF.trap_free_violation([retire], [retire], clean_summary)
        )
        cases = (
            ("spike", [retire, trap], [retire], clean_summary),
            ("dut_trace", [retire], [retire, trap], clean_summary),
            (
                "dut_summary",
                [retire],
                [retire],
                {"kind": "summary", "status": "pass", "traps": 1},
            ),
        )
        for label, spike_events, dut_events, summary in cases:
            with self.subTest(label=label):
                violation = DIFF.trap_free_violation(
                    spike_events, dut_events, summary
                )
                self.assertIsNotNone(violation)
                assert violation is not None
                self.assertEqual(violation["stream"], "trap-free-profile")
                self.assertIn("profile violated", violation["reason"])


if __name__ == "__main__":
    unittest.main()
