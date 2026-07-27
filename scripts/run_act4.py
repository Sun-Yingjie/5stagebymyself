#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

"""Build and run the frozen ACT4 RV32IM_Zicsr regression."""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import hashlib
import json
import os
import shlex
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ACT4_DIR = PROJECT_ROOT / "verification" / "act4"
SOURCE_CONFIG_DIR = ACT4_DIR / "config"
LOCK_FILE = ACT4_DIR / "profile.lock.json"
EXPECTED_TESTS_FILE = ACT4_DIR / "expected_tests.txt"
PROGRAM_FILELIST = PROJECT_ROOT / "tb" / "program" / "rv32_program_tb.f"
ELF_TO_MEM = PROJECT_ROOT / "scripts" / "elf_to_mem.py"
CORE_FILELIST = PROJECT_ROOT / "filelists" / "rv32_core_rtl.f"
ELF_HASH_MANIFEST_NAME = "elf_hash_manifest.json"


class Act4Error(RuntimeError):
    """A user-actionable ACT4 setup or execution error."""


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def hash_files(paths: list[Path]) -> dict[str, str]:
    hashes: dict[str, str] = {}
    for path in sorted(set(paths)):
        if not path.is_file():
            raise Act4Error(f"provenance input is missing: {path}")
        try:
            name = path.relative_to(PROJECT_ROOT).as_posix()
        except ValueError:
            name = str(path.resolve())
        hashes[name] = sha256_file(path)
    return hashes


def project_input_provenance() -> dict[str, dict[str, str]]:
    program_tb_files = [PROGRAM_FILELIST]
    for line in PROGRAM_FILELIST.read_text(encoding="utf-8").splitlines():
        candidate = line.strip()
        if candidate and not candidate.startswith(("#", "+", "-")):
            program_tb_files.append(PROJECT_ROOT / candidate)

    return {
        "dut_rtl_and_filelists": hash_files(
            [CORE_FILELIST, *sorted((PROJECT_ROOT / "rtl").glob("*.sv"))]
        ),
        "program_tb_and_filelist": hash_files(program_tb_files),
        "runner": hash_files([Path(__file__).resolve()]),
        "elf_to_mem_helper": hash_files([ELF_TO_MEM]),
        "act4_config": hash_files(
            [path for path in SOURCE_CONFIG_DIR.iterdir() if path.is_file()]
        ),
        "profile_lock": hash_files([LOCK_FILE]),
        "expected_tests_manifest": hash_files([EXPECTED_TESTS_FILE]),
    }


def tool_provenance(path: Path) -> dict[str, Any]:
    resolved = path.resolve()
    record: dict[str, Any] = {
        "resolved_path": str(resolved),
        "sha256": None,
        "hash_status": "error",
    }
    try:
        record["sha256"] = sha256_file(resolved)
        record["hash_status"] = "ok"
    except OSError as error:
        record["hash_error"] = str(error)
    return record


def project_git_provenance(
    git: Path, environment: dict[str, str]
) -> dict[str, Any]:
    head = run_text(
        [str(git), "-C", str(PROJECT_ROOT), "rev-parse", "HEAD"],
        env=environment,
    )
    status_text = run_text(
        [
            str(git),
            "-C",
            str(PROJECT_ROOT),
            "status",
            "--short",
            "--untracked-files=all",
        ],
        env=environment,
    )
    diff = subprocess.run(
        [str(git), "-C", str(PROJECT_ROOT), "diff", "--binary", "HEAD"],
        env=environment,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if diff.returncode != 0:
        detail = diff.stderr.decode(errors="replace").strip()
        raise Act4Error(f"could not capture project Git diff: {detail}")
    status_lines = status_text.splitlines() if status_text else []
    return {
        "head": head,
        "dirty": bool(status_lines),
        "status_short": status_lines,
        "tracked_diff_sha256": hashlib.sha256(diff.stdout).hexdigest(),
    }


def read_lock() -> dict[str, Any]:
    return json.loads(LOCK_FILE.read_text(encoding="utf-8"))


def read_expected_tests() -> list[str]:
    tests = [line.strip() for line in EXPECTED_TESTS_FILE.read_text(encoding="utf-8").splitlines()]
    return [test for test in tests if test and not test.startswith("#")]


def resolve_executable(value: str | None, fallback: str, label: str) -> Path:
    requested = value or fallback
    if "/" in requested:
        resolved = Path(requested).expanduser().resolve()
        if not resolved.is_file() or not os.access(resolved, os.X_OK):
            raise Act4Error(f"{label} is not executable: {resolved}")
        return resolved
    found = shutil.which(requested)
    if found is None:
        raise Act4Error(f"required {label} was not found: {requested}")
    return Path(found).resolve()


def run_text(command: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise Act4Error(f"command failed ({result.returncode}): {shlex.join(command)}\n{detail}")
    return result.stdout.strip()


def run_logged(
    command: list[str],
    log_file: Path,
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> int:
    log_file.parent.mkdir(parents=True, exist_ok=True)
    print(f"[CMD] {shlex.join(command)}", flush=True)
    with log_file.open("w", encoding="utf-8") as log:
        log.write(f"$ {shlex.join(command)}\n")
        process = subprocess.Popen(
            command,
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        assert process.stdout is not None
        for line in process.stdout:
            print(line, end="", flush=True)
            log.write(line)
        return process.wait()


def run_quiet(
    command: list[str],
    log_file: Path,
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    timeout: int | None = None,
) -> tuple[int, float, str]:
    start = time.monotonic()
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            env=env,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        output = result.stdout + result.stderr
        returncode = result.returncode
    except subprocess.TimeoutExpired as error:
        stdout = error.stdout.decode(errors="replace") if isinstance(error.stdout, bytes) else (error.stdout or "")
        stderr = error.stderr.decode(errors="replace") if isinstance(error.stderr, bytes) else (error.stderr or "")
        output = stdout + stderr + f"\n[ERROR] wall timeout after {timeout}s\n"
        returncode = 124
    elapsed = time.monotonic() - start
    log_file.parent.mkdir(parents=True, exist_ok=True)
    log_file.write_text(f"$ {shlex.join(command)}\n{output}", encoding="utf-8")
    return returncode, elapsed, output


def prepend_tool_dirs(environment: dict[str, str], paths: list[Path]) -> None:
    directories: list[str] = []
    for path in paths:
        directory = str(path.parent)
        if directory not in directories:
            directories.append(directory)
    current = environment.get("PATH", "")
    environment["PATH"] = os.pathsep.join([*directories, current])


def materialize_config(config_dir: Path, tools: dict[str, Path]) -> Path:
    config_dir.mkdir(parents=True, exist_ok=True)
    for name in ("five-stage-rv32im-zicsr.yaml", "link.ld", "rvmodel_macros.h", "sail.json"):
        shutil.copy2(SOURCE_CONFIG_DIR / name, config_dir / name)

    def yaml_string(path: Path) -> str:
        return json.dumps(str(path))

    resolved = "\n".join(
        [
            "# Generated by scripts/run_act4.py; do not edit.",
            "name: five-stage-rv32im-zicsr",
            f"compiler_exe: {yaml_string(tools['gcc'])}",
            f"objdump_exe: {yaml_string(tools['objdump'])}",
            f"ref_model_exe: {yaml_string(tools['sail'])}",
            "udb_config: five-stage-rv32im-zicsr.yaml",
            "linker_script: link.ld",
            "dut_include_dir: .",
            "include_priv_tests: false",
            "",
        ]
    )
    output = config_dir / "test_config.yaml"
    output.write_text(resolved, encoding="utf-8")
    return output


def verify_frozen_inputs(
    act4_root: Path,
    lock: dict[str, Any],
    expected_tests: list[str],
    tools: dict[str, Path],
    environment: dict[str, str],
    *,
    allow_dirty: bool,
) -> dict[str, Any]:
    if not (act4_root / ".git").exists():
        raise Act4Error(f"ACT4_ROOT is not a Git checkout: {act4_root}")
    required = ("Makefile", "run_tests.py", "framework", "tests")
    missing = [name for name in required if not (act4_root / name).exists()]
    if missing:
        raise Act4Error(f"ACT4_ROOT is incomplete; missing: {', '.join(missing)}")

    revision = run_text(
        [str(tools["git"]), "-C", str(act4_root), "rev-parse", "HEAD"],
        env=environment,
    )
    expected_revision = lock["act4"]["revision"]
    if revision != expected_revision:
        raise Act4Error(f"ACT4 revision mismatch: expected {expected_revision}, found {revision}")
    dirty = run_text(
        [
            str(tools["git"]),
            "-C",
            str(act4_root),
            "status",
            "--porcelain",
            "--untracked-files=no",
        ],
        env=environment,
    )
    if dirty and not allow_dirty:
        raise Act4Error("ACT4 checkout has tracked modifications; use --allow-dirty-act4 only for diagnosis")

    act4_diff = subprocess.run(
        [
            str(tools["git"]),
            "-C",
            str(act4_root),
            "diff",
            "--binary",
            "HEAD",
        ],
        env=environment,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if act4_diff.returncode != 0:
        detail = act4_diff.stderr.decode(errors="replace").strip()
        raise Act4Error(f"could not capture ACT4 Git diff: {detail}")

    sail_version = run_text([str(tools["sail"]), "--version"], env=environment)
    expected_sail = lock["reference_model"]["version"]
    if sail_version != expected_sail:
        raise Act4Error(f"Sail version mismatch: expected {expected_sail}, found {sail_version}")

    gcc_version = run_text([str(tools["gcc"]), "-dumpfullversion"], env=environment)
    if int(gcc_version.split(".", maxsplit=1)[0]) < 15:
        raise Act4Error(f"ACT4 requires GCC 15 or newer; found {gcc_version}")
    objdump_version = run_text(
        [str(tools["objdump"]), "--version"], env=environment
    ).splitlines()[0]
    make_version = run_text(
        [str(tools["make"]), "--version"], env=environment
    ).splitlines()[0]

    expected_total = lock["expected_selection"]["total"]
    if len(expected_tests) != expected_total or len(set(expected_tests)) != expected_total:
        raise Act4Error(
            f"frozen manifest is inconsistent: expected {expected_total} unique tests, found {len(set(expected_tests))}"
        )

    config_hashes = {
        path.name: sha256_file(path)
        for path in sorted(SOURCE_CONFIG_DIR.iterdir())
        if path.is_file()
    }
    return {
        "revision": revision,
        "dirty": bool(dirty),
        "status_short": dirty.splitlines() if dirty else [],
        "tracked_diff_sha256": hashlib.sha256(act4_diff.stdout).hexdigest(),
        "sail_version": sail_version,
        "gcc_version": gcc_version,
        "objdump_version": objdump_version,
        "make_version": make_version,
        "config_sha256": config_hashes,
    }


def source_name_from_elf(elf: Path, elf_dir: Path) -> str:
    return str(elf.relative_to(elf_dir).with_suffix(".S"))


def find_generated_elfs(elf_dir: Path) -> dict[str, Path]:
    if not elf_dir.is_dir():
        return {}
    return {
        source_name_from_elf(elf, elf_dir): elf
        for elf in sorted(elf_dir.rglob("*.elf"))
    }


def elf_manifest_bindings(
    input_provenance: dict[str, dict[str, str]],
    lock: dict[str, Any],
    frozen: dict[str, Any],
    generation_tools: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    return {
        "act4_checkout": {
            "revision": frozen["revision"],
            "dirty": frozen["dirty"],
            "status_short": frozen["status_short"],
            "tracked_diff_sha256": frozen["tracked_diff_sha256"],
        },
        "profile_name": lock["profile"]["name"],
        "profile_lock": input_provenance["profile_lock"],
        "expected_tests_manifest": input_provenance[
            "expected_tests_manifest"
        ],
        "act4_config": input_provenance["act4_config"],
        "generation_tools": generation_tools,
    }


def create_elf_hash_manifest(
    expected_tests: list[str],
    generated: dict[str, Path],
    bindings: dict[str, Any],
) -> dict[str, Any]:
    missing = [name for name in expected_tests if name not in generated]
    if missing:
        raise Act4Error(
            f"cannot hash frozen ELFs; {len(missing)} expected file(s) are missing"
        )
    return {
        "schema_version": 1,
        "kind": "act4-frozen-elf-sha256-manifest",
        "test_count": len(expected_tests),
        "bindings": bindings,
        "elfs": {
            name: {
                "path": str(generated[name].resolve()),
                "size_bytes": generated[name].stat().st_size,
                "sha256": sha256_file(generated[name]),
            }
            for name in expected_tests
        },
    }


def verify_elf_hash_manifest(
    manifest_path: Path,
    expected_tests: list[str],
    generated: dict[str, Path],
    bindings: dict[str, Any],
) -> tuple[dict[str, str], dict[str, Any]]:
    if not manifest_path.is_file():
        raise Act4Error(
            "run-only requires the ELF hash manifest from a successful build: "
            f"{manifest_path}"
        )
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise Act4Error(f"could not read ELF hash manifest {manifest_path}: {error}") from error

    errors: list[str] = []
    if manifest.get("schema_version") != 1:
        errors.append("unsupported schema_version")
    if manifest.get("kind") != "act4-frozen-elf-sha256-manifest":
        errors.append("unexpected manifest kind")
    if manifest.get("test_count") != len(expected_tests):
        errors.append(
            f"test_count={manifest.get('test_count')} expected={len(expected_tests)}"
        )
    if manifest.get("bindings") != bindings:
        errors.append("frozen build-input bindings changed")

    entries = manifest.get("elfs")
    if not isinstance(entries, dict):
        errors.append("elfs is not an object")
        entries = {}
    expected_set = set(expected_tests)
    entry_set = set(entries)
    missing_entries = sorted(expected_set - entry_set)
    extra_entries = sorted(entry_set - expected_set)
    if missing_entries:
        errors.append(f"missing hash entries: {', '.join(missing_entries)}")
    if extra_entries:
        errors.append(f"unexpected hash entries: {', '.join(extra_entries)}")

    current_hashes: dict[str, str] = {}
    for name in expected_tests:
        elf = generated.get(name)
        if elf is None or not elf.is_file():
            errors.append(f"missing ELF: {name}")
            continue
        current_hash = sha256_file(elf)
        current_hashes[name] = current_hash
        entry = entries.get(name)
        if not isinstance(entry, dict):
            continue
        expected_hash = entry.get("sha256")
        expected_size = entry.get("size_bytes")
        if expected_hash != current_hash:
            errors.append(
                f"ELF SHA-256 mismatch for {name}: "
                f"expected {expected_hash}, found {current_hash}"
            )
        current_size = elf.stat().st_size
        if expected_size != current_size:
            errors.append(
                f"ELF size mismatch for {name}: "
                f"expected {expected_size}, found {current_size}"
            )

    if errors:
        raise Act4Error("ELF hash manifest verification failed: " + "; ".join(errors))
    return current_hashes, manifest


def preflight_build_cache(
    manifest_path: Path,
    elf_dir: Path,
    expected_tests: list[str],
    bindings: dict[str, Any],
) -> tuple[bool, dict[str, str]]:
    if manifest_path.is_file():
        hashes, _manifest = verify_elf_hash_manifest(
            manifest_path,
            expected_tests,
            find_generated_elfs(elf_dir),
            bindings,
        )
        return True, hashes
    if elf_dir.exists() and any(path.is_file() for path in elf_dir.rglob("*")):
        raise Act4Error(
            "refusing to establish an ELF hash baseline from a non-empty "
            f"output directory without {ELF_HASH_MANIFEST_NAME}: {elf_dir}; "
            "use a new work directory"
        )
    return False, {}


def inspect_elf_load_footprint(
    elf: Path,
    tools: dict[str, Path],
    environment: dict[str, str],
) -> dict[str, Any]:
    output = run_text([str(tools["readelf"]), "-lW", str(elf)], env=environment)
    segments: list[dict[str, Any]] = []
    for line in output.splitlines():
        fields = line.split()
        if not fields or fields[0] != "LOAD":
            continue
        if len(fields) < 6:
            raise Act4Error(f"could not parse PT_LOAD line for {elf}: {line.strip()}")
        virtual_address = int(fields[2], 0)
        physical_address = int(fields[3], 0)
        file_size = int(fields[4], 0)
        memory_size = int(fields[5], 0)
        load_address = physical_address if physical_address != 0 else virtual_address
        load_high = load_address + memory_size
        if load_high > 0x1_0000_0000:
            raise Act4Error(f"PT_LOAD range wraps the 32-bit address space in {elf}")
        segments.append(
            {
                "load_address": f"0x{load_address:08x}",
                "load_high_exclusive": f"0x{load_high:08x}",
                "file_size": file_size,
                "memory_size": memory_size,
            }
        )

    if not segments:
        raise Act4Error(f"ELF contains no PT_LOAD segments: {elf}")
    low = min(int(segment["load_address"], 0) for segment in segments)
    high = max(int(segment["load_high_exclusive"], 0) for segment in segments)
    return {
        "load_low": f"0x{low:08x}",
        "load_high_exclusive": f"0x{high:08x}",
        "span_bytes": high - low,
        "segment_count": len(segments),
        "segments": segments,
    }


def measure_elf_footprints(
    expected_tests: list[str],
    generated: dict[str, Path],
    memory: dict[str, Any],
    tools: dict[str, Path],
    environment: dict[str, str],
) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    test_base = int(memory["test_base"], 0)
    memory_end = test_base + int(memory["size_bytes"])
    tohost = int(memory["tohost"], 0)
    if int(memory["size_bytes"]) <= 0 or int(memory["size_bytes"]) % 4096 != 0:
        raise Act4Error("frozen ACT4 memory size must be a positive 4 KiB multiple")
    if not test_base <= tohost or tohost + 16 > memory_end:
        raise Act4Error("frozen tohost/fromhost mailbox does not fit the ACT4 memory window")

    footprints: dict[str, dict[str, Any]] = {}
    for name in expected_tests:
        footprint = inspect_elf_load_footprint(generated[name], tools, environment)
        low = int(footprint["load_low"], 0)
        high = int(footprint["load_high_exclusive"], 0)
        if low < test_base or high > tohost:
            raise Act4Error(
                f"{name} PT_LOAD range {footprint['load_low']}.."
                f"{footprint['load_high_exclusive']} overlaps the reserved mailbox or lies outside "
                f"0x{test_base:08x}..0x{memory_end:08x}"
            )
        footprint["bytes_before_tohost"] = tohost - high
        footprints[name] = footprint

    maximum_name = max(
        expected_tests,
        key=lambda name: int(footprints[name]["load_high_exclusive"], 0),
    )
    maximum = {"name": maximum_name, **footprints[maximum_name]}
    return footprints, maximum


def compile_program_tb(
    build_dir: Path,
    tools: dict[str, Path],
    environment: dict[str, str],
    memory_size: int,
) -> Path:
    required_files = (CORE_FILELIST, PROGRAM_FILELIST, ELF_TO_MEM)
    missing = [str(path) for path in required_files if not path.is_file()]
    if missing:
        raise Act4Error(f"program runner dependency is missing: {', '.join(missing)}")
    output = build_dir / "tb_rv32_program.vvp"
    command = [
        str(tools["iverilog"]),
        "-g2012",
        "-s",
        "tb_rv32_program",
        f"-Ptb_rv32_program.MEM_BYTES={memory_size}",
        "-o",
        str(output),
        "-f",
        str(CORE_FILELIST),
        "-f",
        str(PROGRAM_FILELIST),
    ]
    returncode = run_logged(command, build_dir / "logs" / "tb.compile.log", cwd=PROJECT_ROOT, env=environment)
    if returncode != 0:
        raise Act4Error("program TB compilation failed; see logs/tb.compile.log")
    return output


def run_one_test(
    source_name: str,
    elf: Path,
    simv: Path,
    run_root: Path,
    tools: dict[str, Path],
    environment: dict[str, str],
    *,
    memory_base: str,
    memory_size: int,
    tohost: str,
    max_cycles: int,
    wall_timeout: int,
) -> dict[str, Any]:
    test_root = run_root / Path(source_name).with_suffix("")
    mem_hex = test_root / "program.hex"
    metadata = test_root / "program.json"
    trace = test_root / "trace.jsonl"
    convert_log = test_root / "convert.log"
    sim_log = test_root / "simulation.log"
    test_root.mkdir(parents=True, exist_ok=True)

    result: dict[str, Any] = {
        "name": source_name,
        "elf": str(elf),
        "status": "fail",
        "reason": "not run",
    }
    convert_command = [
        str(tools["python"]),
        str(ELF_TO_MEM),
        str(elf),
        "-o",
        str(mem_hex),
        "--base",
        memory_base,
        "--size",
        hex(memory_size),
        "--metadata",
        str(metadata),
    ]
    convert_rc, convert_seconds, _ = run_quiet(convert_command, convert_log, cwd=PROJECT_ROOT, env=environment)
    result["conversion"] = {
        "returncode": convert_rc,
        "seconds": round(convert_seconds, 6),
        "log": str(convert_log),
    }
    if convert_rc != 0:
        result["reason"] = "ELF conversion failed"
        return result

    simulation_command = [
        str(tools["vvp"]),
        str(simv),
        f"+MEM_HEX={mem_hex}",
        f"+TRACE={trace}",
        f"+TOHOST={tohost.removeprefix('0x')}",
        f"+MAX_CYCLES={max_cycles}",
    ]
    sim_rc, sim_seconds, _ = run_quiet(
        simulation_command,
        sim_log,
        cwd=PROJECT_ROOT,
        env=environment,
        timeout=wall_timeout,
    )
    result["simulation"] = {
        "returncode": sim_rc,
        "seconds": round(sim_seconds, 6),
        "log": str(sim_log),
        "trace": str(trace),
    }
    if sim_rc == 0:
        result["status"] = "pass"
        result["reason"] = "tohost pass"
    elif sim_rc == 124:
        result["reason"] = f"wall timeout after {wall_timeout}s"
    else:
        result["reason"] = f"simulation exited with status {sim_rc}"
    return result


def count_statuses(tests: list[dict[str, Any]]) -> dict[str, int]:
    counts = {"selected": len(tests), "generated": 0, "run": 0, "pass": 0, "fail": 0, "skip": 0}
    for test in tests:
        if test.get("elf"):
            counts["generated"] += 1
        status = test.get("status")
        if status in ("pass", "fail"):
            counts["run"] += 1
            counts[status] += 1
        elif status == "skip":
            counts["skip"] += 1
    return counts


def write_report(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(f"{path.suffix}.tmp")
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def begin_report(path: Path, report: dict[str, Any]) -> str:
    run_id = uuid.uuid4().hex
    report["run_id"] = run_id
    report["status"] = "running"
    write_report(path, report)
    return run_id


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=("all", "build", "run"), default="all")
    parser.add_argument("--act4-root", default=os.environ.get("ACT4_ROOT"))
    parser.add_argument("--work-dir", type=Path, default=PROJECT_ROOT / "out" / "act4")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--jobs", type=int, default=max(1, min(8, os.cpu_count() or 1)))
    parser.add_argument("--run-jobs", type=int, default=max(1, min(4, os.cpu_count() or 1)))
    parser.add_argument("--max-cycles", type=int, default=2_000_000)
    parser.add_argument("--wall-timeout", type=int, default=300)
    parser.add_argument("--gcc", default=os.environ.get("RISCV_GCC"))
    parser.add_argument("--objdump", default=os.environ.get("RISCV_OBJDUMP"))
    parser.add_argument("--readelf", default=os.environ.get("RISCV_READELF"))
    parser.add_argument("--sail", default=os.environ.get("SAIL") or os.environ.get("SAIL_RISCV_SIM"))
    parser.add_argument("--make", dest="make_exe", default=os.environ.get("MAKE"))
    parser.add_argument("--python", default=os.environ.get("PYTHON"))
    parser.add_argument("--iverilog", default=os.environ.get("IVERILOG"))
    parser.add_argument("--vvp", default=os.environ.get("VVP"))
    parser.add_argument("--uv", default=os.environ.get("UV"))
    parser.add_argument("--ruby", default=os.environ.get("RUBY"))
    parser.add_argument("--bundle", default=os.environ.get("BUNDLE"))
    parser.add_argument("--path-prepend", action="append", default=[])
    parser.add_argument("--bundle-gemfile", default=os.environ.get("BUNDLE_GEMFILE"))
    parser.add_argument("--bundle-path", default=os.environ.get("BUNDLE_PATH"))
    parser.add_argument("--xdg-cache-home", default=os.environ.get("XDG_CACHE_HOME"))
    parser.add_argument("--allow-dirty-act4", action="store_true")
    parser.add_argument(
        "--allow-manifest-drift",
        action="store_true",
        help="allow extra generated ELFs; missing frozen tests always fail",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    started = utc_now()
    work_dir = args.work_dir.expanduser().resolve()
    report_path = (args.report or work_dir / "report.json").expanduser().resolve()
    lock: dict[str, Any] = {}
    expected_tests: list[str] = []
    report: dict[str, Any] = {
        "schema_version": 1,
        "started_at": started,
        "finished_at": None,
        "phase": args.phase,
        "status": "running",
        "profile": None,
        "selection": [],
        "tests": [],
        "counts": {
            "selected": 0,
            "generated": 0,
            "run": 0,
            "pass": 0,
            "fail": 0,
            "skip": 0,
        },
        "errors": [],
    }
    begin_report(report_path, report)

    exit_code = 1
    try:
        lock = read_lock()
        expected_tests = read_expected_tests()
        report["profile"] = lock
        report["selection"] = expected_tests
        report["counts"]["selected"] = len(expected_tests)
        if not args.act4_root:
            raise Act4Error("ACT4_ROOT or --act4-root is required")
        if args.jobs < 1 or args.run_jobs < 1:
            raise Act4Error("--jobs and --run-jobs must be positive")
        if args.max_cycles < 1 or args.wall_timeout < 1:
            raise Act4Error("--max-cycles and --wall-timeout must be positive")

        act4_root = Path(args.act4_root).expanduser().resolve()
        tools = {
            "gcc": resolve_executable(args.gcc, "riscv64-unknown-elf-gcc", "RISC-V GCC"),
            "objdump": resolve_executable(args.objdump, "riscv64-unknown-elf-objdump", "RISC-V objdump"),
            "readelf": resolve_executable(
                args.readelf,
                "riscv64-unknown-elf-readelf",
                "RISC-V readelf",
            ),
            "sail": resolve_executable(args.sail, "sail_riscv_sim", "Sail model"),
            "make": resolve_executable(args.make_exe, "make", "make"),
            "python": resolve_executable(args.python, "python3", "Python"),
            "git": resolve_executable(None, "git", "Git"),
        }
        if args.phase in ("all", "run"):
            tools["iverilog"] = resolve_executable(args.iverilog, "iverilog", "Icarus Verilog")
            tools["vvp"] = resolve_executable(args.vvp, "vvp", "vvp")

        optional_tools: dict[str, Path] = {}
        for name, value, fallback, label in (
            ("bundle", args.bundle, "bundle", "Bundler"),
            ("ruby", args.ruby, "ruby", "Ruby"),
            ("uv", args.uv, "uv", "uv"),
        ):
            try:
                optional_tools[name] = resolve_executable(value, fallback, label)
            except Act4Error:
                if value:
                    raise
        extra_dirs = [Path(path).expanduser().resolve() for path in args.path_prepend]
        for directory in extra_dirs:
            if not directory.is_dir():
                raise Act4Error(f"--path-prepend is not a directory: {directory}")

        environment = os.environ.copy()
        # The explicitly selected Bundler must precede Ruby's bundled `bundle`,
        # and both must precede /usr/bin. Otherwise macOS can silently rewrite
        # the frozen Gemfile.lock with a different Bundler version.
        prepend_tool_dirs(environment, [*optional_tools.values(), *tools.values()])
        if extra_dirs:
            environment["PATH"] = os.pathsep.join([*(str(path) for path in extra_dirs), environment["PATH"]])
        for key, value in (
            ("BUNDLE_GEMFILE", args.bundle_gemfile),
            ("BUNDLE_PATH", args.bundle_path),
            ("XDG_CACHE_HOME", args.xdg_cache_home),
        ):
            if value:
                environment[key] = str(Path(value).expanduser().resolve())

        input_provenance = project_input_provenance()
        all_tool_paths = {**tools, **optional_tools}
        report["provenance"] = {
            "project_git": project_git_provenance(tools["git"], environment),
            "inputs": input_provenance,
            "tools": {
                name: tool_provenance(path)
                for name, path in sorted(all_tool_paths.items())
            },
        }

        frozen = verify_frozen_inputs(
            act4_root,
            lock,
            expected_tests,
            tools,
            environment,
            allow_dirty=args.allow_dirty_act4,
        )
        generation_versions = {
            "sail": frozen["sail_version"],
            "gcc": frozen["gcc_version"],
            "objdump": frozen["objdump_version"],
            "make": frozen["make_version"],
        }
        if "bundle" in optional_tools:
            generation_versions["bundle"] = run_text(
                [str(optional_tools["bundle"]), "--version"],
                env=environment,
            )
        generation_tools: dict[str, dict[str, Any]] = {}
        for name in ("sail", "gcc", "objdump", "make", "bundle"):
            path = all_tool_paths.get(name)
            if path is None:
                generation_tools[name] = {
                    "resolved_path": None,
                    "sha256": None,
                    "hash_status": "unavailable",
                    "version": None,
                }
            else:
                generation_tools[name] = {
                    **tool_provenance(path),
                    "version": generation_versions[name],
                }
        report["provenance"]["generation_tools"] = generation_tools
        report["environment"] = {
            "act4_root": str(act4_root),
            "work_dir": str(work_dir),
            "tools": {
                name: str(path) for name, path in sorted(all_tool_paths.items())
            },
            "generation_tool_versions": generation_versions,
            **frozen,
        }
        print(
            f"[INFO] ACT4 {frozen['revision']} / Sail {frozen['sail_version']} / "
            f"selected {len(expected_tests)} tests",
            flush=True,
        )

        config_file = materialize_config(work_dir / "resolved-config", tools)
        act_work = work_dir / "act-work"
        elf_dir = act_work / lock["profile"]["name"] / "elfs"
        elf_hash_manifest_path = work_dir / ELF_HASH_MANIFEST_NAME
        elf_hash_bindings = elf_manifest_bindings(
            input_provenance,
            lock,
            frozen,
            generation_tools,
        )

        preexisting_elf_manifest = False
        if args.phase in ("all", "build"):
            preexisting_elf_manifest, cached_hashes = preflight_build_cache(
                elf_hash_manifest_path,
                elf_dir,
                expected_tests,
                elf_hash_bindings,
            )
            if preexisting_elf_manifest:
                report["elf_hash_manifest_prebuild"] = {
                    "status": "pass",
                    "mode": "verified_existing_before_build",
                    "path": str(elf_hash_manifest_path),
                    "sha256": sha256_file(elf_hash_manifest_path),
                    "test_count": len(cached_hashes),
                }

        build_ok = True
        if args.phase in ("all", "build"):
            build_command = [
                str(tools["make"]),
                "-C",
                str(act4_root),
                f"-j{args.jobs}",
                "elfs",
                f"CONFIG_FILES={config_file}",
                f"WORKDIR={act_work}",
                "EXTENSIONS=I,M,Zicsr",
                "EXCLUDE_EXTENSIONS=Sm,SdtrigSm,SdtrigS,SdtrigU",
                f"JOBS={args.jobs}",
                "FAST=True",
            ]
            build_rc = run_logged(build_command, work_dir / "logs" / "act4-build.log", env=environment)
            report["build"] = {
                "command": build_command,
                "returncode": build_rc,
                "log": str(work_dir / "logs" / "act4-build.log"),
            }
            build_ok = build_rc == 0
        else:
            report["build"] = {"status": "not_requested"}

        generated = find_generated_elfs(elf_dir)
        selected_set = set(expected_tests)
        generated_set = set(generated)
        missing_elfs = sorted(selected_set - generated_set)
        extra_elfs = sorted(generated_set - selected_set)
        report["generated_manifest"] = sorted(generated_set)
        report["manifest_drift"] = {"missing": missing_elfs, "extra": extra_elfs}

        if missing_elfs:
            build_ok = False
            report["errors"].append(
                f"manifest drift: {len(missing_elfs)} frozen ELF(s) are missing"
            )
        if extra_elfs and not args.allow_manifest_drift:
            build_ok = False
            report["errors"].append(f"manifest drift: {len(extra_elfs)} unexpected ELF(s) were generated")

        elf_hashes: dict[str, str] = {}
        if build_ok:
            manifest_mode = "verified" if args.phase == "run" else "created"
            try:
                if args.phase == "run":
                    elf_hashes, _elf_hash_manifest = verify_elf_hash_manifest(
                        elf_hash_manifest_path,
                        expected_tests,
                        generated,
                        elf_hash_bindings,
                    )
                elif preexisting_elf_manifest:
                    elf_hashes, _elf_hash_manifest = verify_elf_hash_manifest(
                        elf_hash_manifest_path,
                        expected_tests,
                        generated,
                        elf_hash_bindings,
                    )
                    manifest_mode = "verified_existing_after_build"
                else:
                    _elf_hash_manifest = create_elf_hash_manifest(
                        expected_tests,
                        generated,
                        elf_hash_bindings,
                    )
                    write_report(elf_hash_manifest_path, _elf_hash_manifest)
                    elf_hashes = {
                        name: _elf_hash_manifest["elfs"][name]["sha256"]
                        for name in expected_tests
                    }
                report["elf_hash_manifest"] = {
                    "status": "pass",
                    "mode": manifest_mode,
                    "path": str(elf_hash_manifest_path),
                    "sha256": sha256_file(elf_hash_manifest_path),
                    "test_count": len(elf_hashes),
                }
                report["elf_sha256"] = elf_hashes
            except (Act4Error, OSError, ValueError) as error:
                build_ok = False
                report["elf_hash_manifest"] = {
                    "status": "fail",
                    "mode": manifest_mode,
                    "path": str(elf_hash_manifest_path),
                    "error": str(error),
                }
                report["errors"].append(str(error))

        footprints: dict[str, dict[str, Any]] = {}
        memory = lock["memory"]
        if build_ok:
            try:
                footprints, maximum_footprint = measure_elf_footprints(
                    expected_tests,
                    generated,
                    memory,
                    tools,
                    environment,
                )
                report["elf_footprints"] = footprints
                report["maximum_load_footprint"] = maximum_footprint
            except (Act4Error, ValueError) as error:
                build_ok = False
                report["errors"].append(str(error))
        if not build_ok:
            for name in expected_tests:
                test = {
                    "name": name,
                    "elf": str(generated[name]) if name in generated else None,
                    "status": "skip",
                    "reason": "ACT4 build, manifest, or ELF-footprint check failed",
                }
                if name in footprints:
                    test["elf_footprint"] = footprints[name]
                if name in elf_hashes:
                    test["elf_sha256"] = elf_hashes[name]
                report["tests"].append(test)
            raise Act4Error("ACT4 ELF generation did not complete exactly; see the build log and report")

        if args.phase == "build":
            report["tests"] = [
                {
                    "name": name,
                    "elf": str(generated[name]),
                    "status": "generated",
                    "reason": "build-only phase",
                    "elf_footprint": footprints[name],
                    "elf_sha256": elf_hashes[name],
                }
                for name in expected_tests
            ]
            report["counts"] = count_statuses(report["tests"])
            report["status"] = "pass"
            exit_code = 0
        else:
            try:
                simv = compile_program_tb(
                    work_dir,
                    tools,
                    environment,
                    int(memory["size_bytes"]),
                )
                report["simulation_binary"] = {
                    "path": str(simv.resolve()),
                    "size_bytes": simv.stat().st_size,
                    "sha256": sha256_file(simv),
                }
            except Act4Error as error:
                report["tests"] = [
                    {
                        "name": name,
                        "elf": str(generated[name]),
                        "status": "skip",
                        "reason": str(error),
                        "elf_footprint": footprints[name],
                        "elf_sha256": elf_hashes[name],
                    }
                    for name in expected_tests
                ]
                raise

            run_root = work_dir / "runs"
            test_results: dict[str, dict[str, Any]] = {}
            with concurrent.futures.ThreadPoolExecutor(max_workers=args.run_jobs) as executor:
                futures = {
                    executor.submit(
                        run_one_test,
                        name,
                        generated[name],
                        simv,
                        run_root,
                        tools,
                        environment,
                        memory_base=memory["test_base"],
                        memory_size=memory["size_bytes"],
                        tohost=memory["tohost"],
                        max_cycles=args.max_cycles,
                        wall_timeout=args.wall_timeout,
                    ): name
                    for name in expected_tests
                }
                for future in concurrent.futures.as_completed(futures):
                    name = futures[future]
                    try:
                        result = future.result()
                    except Exception as error:  # keep the batch observable and complete
                        result = {
                            "name": name,
                            "elf": str(generated[name]),
                            "status": "fail",
                            "reason": f"runner exception: {error}",
                        }
                    result["elf_footprint"] = footprints[name]
                    result["elf_sha256"] = elf_hashes[name]
                    test_results[name] = result
                    if result["status"] == "pass":
                        print(f'RVCP-SUMMARY: TEST PASSED - Test File "{Path(name).name}"', flush=True)
                    else:
                        print(
                            f'RVCP-SUMMARY: TEST FAILED - Test File "{Path(name).name}" '
                            f'({result["reason"]})',
                            flush=True,
                        )

            report["tests"] = [test_results[name] for name in expected_tests]
            report["counts"] = count_statuses(report["tests"])
            if report["counts"]["pass"] == len(expected_tests):
                report["status"] = "pass"
                exit_code = 0
            else:
                report["status"] = "fail"
                exit_code = 1

    except (Act4Error, OSError, ValueError, KeyError) as error:
        message = str(error)
        report["errors"].append(message)
        if not report["tests"]:
            report["tests"] = [
                {"name": name, "elf": None, "status": "skip", "reason": message}
                for name in expected_tests
            ]
        report["counts"] = count_statuses(report["tests"])
        report["status"] = "error"
        print(f"[ERROR] {message}", file=sys.stderr, flush=True)
        exit_code = 1
    finally:
        report["finished_at"] = utc_now()
        write_report(report_path, report)
        print(
            "[SUMMARY] "
            + " ".join(f"{key}={value}" for key, value in report["counts"].items())
            + f" report={report_path}",
            flush=True,
        )

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
