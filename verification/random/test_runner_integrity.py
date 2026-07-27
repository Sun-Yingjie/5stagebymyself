#!/usr/bin/env python3
"""Negative tests for D5 seed/result integrity checks."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER_PATH = REPO_ROOT / "scripts/run_random_regression.py"
SPEC = importlib.util.spec_from_file_location("run_random_regression", RUNNER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {RUNNER_PATH}")
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


def result_line(seed: str) -> str:
    return (
        "[D5_RESULT] status=PASS "
        f"seed={seed} "
        "cycles=100 retire=17 trap=1 dmem=4 mdu_req=2 mdu_rsp=2 irq=0 "
        "checks=200 imem_req_stall=1 imem_rsp_delay=1 dmem_req_stall=1 "
        "dmem_rsp_delay=1 imem_req_low=1 imem_rsp_low=1 dmem_req_low=1 "
        "dmem_rsp_low=1 imem_req_forced=0 imem_rsp_forced=0 "
        "dmem_req_forced=0 dmem_rsp_forced=0 imem_req_max=1 "
        "imem_rsp_max=1 dmem_req_max=1 dmem_rsp_max=1 coverage=03ff "
        "state=12345678"
    )


class RunnerIntegrityTest(unittest.TestCase):
    def test_wrong_reported_seed_is_a_validation_error(self) -> None:
        parsed_results = RUNNER.parse_d5_results(result_line("00000002"))
        _parsed, errors = RUNNER.validate_run_result(
            parsed_results, "00000001", 8
        )
        self.assertIn("reported_seed=00000002_expected_00000001", errors)

    def test_duplicate_results_are_rejected(self) -> None:
        output = "\n".join(
            (result_line("00000001"), result_line("00000001"))
        )
        _parsed, errors = RUNNER.validate_run_result(
            RUNNER.parse_d5_results(output), "00000001", 8
        )
        self.assertIn("duplicate_d5_results=2_expected_1", errors)

        duplicate_rows = [
            {"sim": "icarus", "requested_seed": "00000001"},
            {"sim": "icarus", "requested_seed": "00000001"},
        ]
        matrix_errors = RUNNER.validate_result_matrix(
            duplicate_rows, ["icarus"], ["00000001"]
        )
        self.assertEqual(matrix_errors[0]["kind"], "duplicate_result")
        self.assertEqual(matrix_errors[0]["count"], 2)

    def test_missing_cross_sim_result_is_rejected(self) -> None:
        rows = [{"sim": "icarus", "requested_seed": "00000001"}]
        errors = RUNNER.validate_result_matrix(
            rows, ["icarus", "verilator"], ["00000001"]
        )
        self.assertEqual(
            errors,
            [
                {
                    "kind": "missing_result",
                    "sim": "verilator",
                    "requested_seed": "00000001",
                    "count": 0,
                }
            ],
        )
        both_missing = RUNNER.validate_result_matrix(
            [], ["icarus", "verilator"], ["00000001"]
        )
        self.assertEqual(len(both_missing), 2)
        self.assertTrue(
            all(error["kind"] == "missing_result" for error in both_missing)
        )

    def test_missing_schema_field_is_rejected(self) -> None:
        parsed = RUNNER.parse_d5_results(result_line("00000001"))[0]
        del parsed["dmem_rsp_delay"]
        _parsed, errors = RUNNER.validate_run_result(
            [parsed], "00000001", 8
        )
        self.assertIn("missing_required_fields=dmem_rsp_delay", errors)

    def test_wrong_fixed_oracle_count_is_rejected(self) -> None:
        parsed = RUNNER.parse_d5_results(result_line("00000001"))[0]
        parsed["retire"] = "18"
        _parsed, errors = RUNNER.validate_run_result(
            [parsed], "00000001", 8
        )
        self.assertIn("oracle_retire=18_expected_17", errors)

    def test_two_invalid_rows_cannot_match_on_shared_missing_fields(self) -> None:
        mismatch = RUNNER.compare_cross_sim_rows(
            {"status": "FAIL"}, {"status": "FAIL"}
        )
        self.assertEqual(mismatch["validated_status"], ("FAIL", "FAIL"))

    def test_begin_summary_replaces_stale_pass_atomically(self) -> None:
        with tempfile.TemporaryDirectory(prefix="d5-stale-summary.") as tmp:
            root = Path(tmp)
            summary_path = root / "summary.json"
            RUNNER.write_json(
                summary_path, {"status": "PASS", "run_id": "stale-run"}
            )
            run_id = RUNNER.begin_summary(summary_path, root, "test-time")
            running = json.loads(summary_path.read_text(encoding="utf-8"))
            self.assertEqual(running["status"], "running")
            self.assertEqual(running["run_id"], run_id)
            self.assertNotEqual(run_id, "stale-run")
            self.assertFalse(summary_path.with_suffix(".json.tmp").exists())

    def test_duplicate_input_writes_failure_report_and_returns_nonzero(self) -> None:
        with tempfile.TemporaryDirectory(prefix="d5-duplicate-seed.") as tmp:
            completed = subprocess.run(
                [
                    sys.executable,
                    str(RUNNER_PATH),
                    "--sim",
                    "icarus",
                    "--seeds",
                    "1,0x1",
                    "--results-root",
                    tmp,
                ],
                cwd=REPO_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertEqual(completed.returncode, 1)
            summary = json.loads(
                (Path(tmp) / "summary.json").read_text(encoding="utf-8")
            )
            self.assertEqual(summary["status"], "FAIL")
            self.assertRegex(summary["run_id"], r"^[0-9a-f]{32}$")
            self.assertEqual(
                summary["result_integrity_errors"],
                [
                    {
                        "kind": "duplicate_input_seed",
                        "requested_seed": "00000001",
                        "count": 2,
                    }
                ],
            )

    def test_wrong_echo_writes_failed_row_and_returns_nonzero(self) -> None:
        with tempfile.TemporaryDirectory(prefix="d5-wrong-echo.") as tmp:
            root = Path(tmp)
            fake_bin = root / "bin"
            results = root / "results"
            fake_bin.mkdir()

            iverilog = fake_bin / "iverilog"
            iverilog.write_text("#!/bin/sh\necho fake-iverilog\n", encoding="utf-8")
            iverilog.chmod(0o755)

            vvp = fake_bin / "vvp"
            vvp.write_text(
                "#!/bin/sh\n"
                "echo '[D5_RESULT] status=PASS seed=00000002 cycles=1 "
                "retire=17 trap=1 dmem=4 mdu_req=2 mdu_rsp=2 irq=0 checks=1 "
                "imem_req_stall=1 imem_rsp_delay=1 dmem_req_stall=1 "
                "dmem_rsp_delay=1 imem_req_low=1 imem_rsp_low=1 "
                "dmem_req_low=1 dmem_rsp_low=1 imem_req_forced=0 "
                "imem_rsp_forced=0 dmem_req_forced=0 dmem_rsp_forced=0 "
                "imem_req_max=1 imem_rsp_max=1 dmem_req_max=1 dmem_rsp_max=1 "
                "coverage=03ff state=00000001'\n",
                encoding="utf-8",
            )
            vvp.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = f"{fake_bin}{os.pathsep}{environment['PATH']}"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(RUNNER_PATH),
                    "--sim",
                    "icarus",
                    "--seeds",
                    "1",
                    "--results-root",
                    str(results),
                    "--no-failure-replay",
                    "--command-timeout",
                    "5",
                ],
                cwd=REPO_ROOT,
                env=environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertEqual(completed.returncode, 1)
            summary = json.loads(
                (results / "summary.json").read_text(encoding="utf-8")
            )
            self.assertEqual(summary["status"], "FAIL")
            self.assertEqual(summary["fail_count"], 1)
            row = json.loads(
                (results / "summary.jsonl").read_text(encoding="utf-8")
            )
            self.assertEqual(row["requested_seed"], "00000001")
            self.assertEqual(row["seed"], "00000001")
            self.assertEqual(row["reported_seed"], "00000002")
            self.assertEqual(row["status"], "FAIL")
            self.assertIn(
                "reported_seed=00000002_expected_00000001",
                row["validation_errors"],
            )


if __name__ == "__main__":
    unittest.main()
