#!/usr/bin/env python3
"""Pure-Python checks for ACT4 build/run provenance gates."""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER_PATH = REPO_ROOT / "scripts/run_act4.py"
SPEC = importlib.util.spec_from_file_location("run_act4", RUNNER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {RUNNER_PATH}")
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class Act4ProvenanceTest(unittest.TestCase):
    def test_core_filelist_covers_and_hashes_all_rtl_sources(self) -> None:
        listed_sources = set(RUNNER.read_filelist_sources(RUNNER.CORE_FILELIST))
        rtl_sources = set((REPO_ROOT / "rtl").rglob("*.sv"))
        self.assertEqual(listed_sources, rtl_sources)

        hashes = RUNNER.project_input_provenance()["dut_rtl_and_filelists"]
        expected_paths = {RUNNER.CORE_FILELIST, *listed_sources}
        expected_names = {
            path.relative_to(REPO_ROOT).as_posix() for path in expected_paths
        }
        self.assertEqual(set(hashes), expected_names)
        for path in expected_paths:
            name = path.relative_to(REPO_ROOT).as_posix()
            self.assertEqual(hashes[name], RUNNER.sha256_file(path))

    def test_begin_report_replaces_stale_pass_with_new_running_id(self) -> None:
        with tempfile.TemporaryDirectory(prefix="act4-stale-report.") as tmp:
            report_path = Path(tmp) / "report.json"
            RUNNER.write_report(
                report_path, {"status": "pass", "run_id": "stale-run"}
            )
            report = {"status": "error", "tests": []}
            run_id = RUNNER.begin_report(report_path, report)
            running = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(running["status"], "running")
            self.assertEqual(running["run_id"], run_id)
            self.assertNotEqual(run_id, "stale-run")
            self.assertFalse(report_path.with_suffix(".json.tmp").exists())

    def test_run_only_rejects_tampered_elf(self) -> None:
        with tempfile.TemporaryDirectory(prefix="act4-elf-provenance.") as tmp:
            root = Path(tmp)
            names = ["rv32i/I/I-addi-00.S", "rv32m/M/M-mul-00.S"]
            generated = {
                name: root / Path(name).with_suffix(".elf") for name in names
            }
            for index, elf in enumerate(generated.values()):
                elf.parent.mkdir(parents=True, exist_ok=True)
                elf.write_bytes(b"ELF-fixture-" + bytes([index]))

            bindings = {
                "act4_revision": "frozen-revision",
                "profile_name": "test-profile",
            }
            manifest_path = root / "elf_hash_manifest.json"
            manifest = RUNNER.create_elf_hash_manifest(
                names, generated, bindings
            )
            RUNNER.write_report(manifest_path, manifest)

            hashes, _loaded = RUNNER.verify_elf_hash_manifest(
                manifest_path, names, generated, bindings
            )
            self.assertEqual(set(hashes), set(names))

            generated[names[0]].write_bytes(b"tampered-ELF")
            with self.assertRaisesRegex(
                RUNNER.Act4Error,
                r"ELF SHA-256 mismatch for rv32i/I/I-addi-00\.S",
            ):
                RUNNER.verify_elf_hash_manifest(
                    manifest_path, names, generated, bindings
                )

    def test_run_only_requires_prior_build_manifest(self) -> None:
        with tempfile.TemporaryDirectory(prefix="act4-missing-manifest.") as tmp:
            missing = Path(tmp) / "elf_hash_manifest.json"
            with self.assertRaisesRegex(
                RUNNER.Act4Error, r"run-only requires the ELF hash manifest"
            ):
                RUNNER.verify_elf_hash_manifest(
                    missing,
                    [],
                    {},
                    {"act4_revision": "frozen-revision"},
                )

    def test_new_build_refuses_nonempty_unbound_elf_cache(self) -> None:
        with tempfile.TemporaryDirectory(prefix="act4-unbound-cache.") as tmp:
            root = Path(tmp)
            elf_dir = root / "elfs"
            elf = elf_dir / "rv32i/I/I-addi-00.elf"
            elf.parent.mkdir(parents=True)
            elf.write_bytes(b"unbound-cache")
            with self.assertRaisesRegex(
                RUNNER.Act4Error, r"refusing to establish an ELF hash baseline"
            ):
                RUNNER.preflight_build_cache(
                    root / "elf_hash_manifest.json",
                    elf_dir,
                    ["rv32i/I/I-addi-00.S"],
                    {"act4_revision": "frozen-revision"},
                )

    def test_tool_record_hashes_script_file(self) -> None:
        with tempfile.TemporaryDirectory(prefix="act4-tool-provenance.") as tmp:
            tool = Path(tmp) / "tool"
            tool.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            record = RUNNER.tool_provenance(tool)
            self.assertEqual(record["resolved_path"], str(tool.resolve()))
            self.assertEqual(record["hash_status"], "ok")
            self.assertEqual(record["sha256"], RUNNER.sha256_file(tool))


if __name__ == "__main__":
    unittest.main()
