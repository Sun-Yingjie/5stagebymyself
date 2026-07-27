#!/usr/bin/env python3
"""Negative tests for reused differential artifact directories."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts/run_differential.py"
SPEC = importlib.util.spec_from_file_location("run_differential_lifecycle", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {MODULE_PATH}")
DIFF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DIFF)


class ArtifactLifecycleTest(unittest.TestCase):
    def test_provenance_covers_filelists_sources_and_git_state(self) -> None:
        rtl = DIFF.filelist_record(REPO_ROOT / "filelists/rv32_core_rtl.f", REPO_ROOT)
        program_tb = DIFF.filelist_record(
            REPO_ROOT / "tb/program/rv32_program_tb.f",
            REPO_ROOT,
        )
        git = DIFF.git_provenance(REPO_ROOT)

        self.assertEqual(rtl["filelist"]["path"], "filelists/rv32_core_rtl.f")
        self.assertEqual(len(rtl["sources"]), 17)
        self.assertIn("rtl/rv32_core.sv", {item["path"] for item in rtl["sources"]})
        self.assertEqual(
            {item["path"] for item in program_tb["sources"]},
            {"tb/program/tb_rv32_program.sv"},
        )
        for record in [rtl["filelist"], *rtl["sources"], *program_tb["sources"]]:
            self.assertRegex(record["sha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(git["head"], r"^[0-9a-f]{40}$")
        self.assertEqual(
            git["status_summary"]["entries"],
            len(git["status_porcelain"]),
        )

    def test_running_state_is_published_before_tool_preflight(self) -> None:
        with tempfile.TemporaryDirectory(prefix="rv32-differential-running.") as tmp:
            artifact_dir = Path(tmp)
            (artifact_dir / "comparison.json").write_text(
                '{"status":"pass","run_id":"stale-run"}\n',
                encoding="utf-8",
            )
            (artifact_dir / "first_divergence.json").write_text(
                '{"status":"mismatch","run_id":"stale-run"}\n',
                encoding="utf-8",
            )
            observed: dict[str, dict[str, object]] = {}

            def inspect_then_fail(_name: str) -> str:
                observed["comparison"] = json.loads(
                    (artifact_dir / "comparison.json").read_text(encoding="utf-8")
                )
                observed["divergence"] = json.loads(
                    (artifact_dir / "first_divergence.json").read_text(
                        encoding="utf-8"
                    )
                )
                raise DIFF.DifferentialError("intentional tool-preflight failure")

            with mock.patch.object(DIFF, "find_tool", side_effect=inspect_then_fail):
                with contextlib.redirect_stdout(
                    io.StringIO()
                ), contextlib.redirect_stderr(io.StringIO()):
                    returncode = DIFF.main(["--build-dir", str(artifact_dir)])

            self.assertEqual(returncode, 2)
            self.assertEqual(observed["comparison"]["status"], "running")
            self.assertEqual(observed["divergence"]["status"], "pending")
            self.assertNotEqual(observed["comparison"]["run_id"], "stale-run")
            self.assertEqual(
                observed["comparison"]["run_id"],
                observed["divergence"]["run_id"],
            )

    def test_preflight_error_replaces_stale_pass_and_divergence(self) -> None:
        with tempfile.TemporaryDirectory(prefix="rv32-differential-lifecycle.") as tmp:
            artifact_dir = Path(tmp)
            stale_run_id = "stale-run"
            (artifact_dir / "comparison.json").write_text(
                json.dumps({"status": "pass", "run_id": stale_run_id}) + "\n",
                encoding="utf-8",
            )
            (artifact_dir / "first_divergence.json").write_text(
                json.dumps(
                    {
                        "status": "mismatch",
                        "run_id": stale_run_id,
                        "reason": "stale divergence",
                    }
                )
                + "\n",
                encoding="utf-8",
            )

            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(
                io.StringIO()
            ):
                returncode = DIFF.main(
                    [
                        "--build-dir",
                        str(artifact_dir),
                        "--max-cycles",
                        "0",
                    ]
                )

            self.assertEqual(returncode, 2)
            comparison = json.loads(
                (artifact_dir / "comparison.json").read_text(encoding="utf-8")
            )
            divergence = json.loads(
                (artifact_dir / "first_divergence.json").read_text(encoding="utf-8")
            )
            manifest = json.loads(
                (artifact_dir / "manifest.json").read_text(encoding="utf-8")
            )

            self.assertEqual(comparison["status"], "error")
            self.assertEqual(divergence["status"], "error")
            self.assertEqual(manifest["status"], "error")
            self.assertNotEqual(comparison["run_id"], stale_run_id)
            self.assertEqual(comparison["run_id"], divergence["run_id"])
            self.assertEqual(comparison["run_id"], manifest["run_id"])
            self.assertIsNone(comparison["first_divergence"])
            self.assertIsNone(divergence["first_divergence"])
            self.assertIn("--max-cycles must be positive", comparison["error"])
            self.assertNotIn("stale divergence", json.dumps(divergence))
            self.assertEqual(list(artifact_dir.glob(".*.tmp")), [])


if __name__ == "__main__":
    unittest.main()
