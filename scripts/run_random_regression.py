#!/usr/bin/env python3
"""Run reproducible D5 random-backpressure campaigns.

The script uses only the Python standard library.  Each simulator is compiled
once, then the resulting executable is reused for every seed.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import time
import uuid
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]

D5_DECIMAL_FIELDS = (
    "cycles",
    "retire",
    "trap",
    "dmem",
    "mdu_req",
    "mdu_rsp",
    "irq",
    "checks",
    "imem_req_stall",
    "imem_rsp_delay",
    "dmem_req_stall",
    "dmem_rsp_delay",
    "imem_req_low",
    "imem_rsp_low",
    "dmem_req_low",
    "dmem_rsp_low",
    "imem_req_forced",
    "imem_rsp_forced",
    "dmem_req_forced",
    "dmem_rsp_forced",
    "imem_req_max",
    "imem_rsp_max",
    "dmem_req_max",
    "dmem_rsp_max",
)
D5_HEX_FIELDS = ("coverage", "state")
D5_REQUIRED_FIELDS = ("status", "seed", *D5_DECIMAL_FIELDS, *D5_HEX_FIELDS)
D5_ORACLE = {
    "retire": 17,
    "trap": 1,
    "dmem": 4,
    "mdu_req": 2,
    "mdu_rsp": 2,
    "irq": 0,
}
D5_COMPARE_FIELDS = (*D5_DECIMAL_FIELDS, *D5_HEX_FIELDS)


def parse_seeds(value: str) -> list[int]:
    def parse_one(token: str) -> int:
        try:
            return int(token, 0)
        except ValueError:
            return int(token, 16)

    seeds: list[int] = []
    for token in value.split(","):
        token = token.strip()
        if not token:
            continue
        if ".." in token:
            start_text, end_text = token.split("..", 1)
            start = parse_one(start_text)
            end = parse_one(end_text)
            if end < start:
                raise argparse.ArgumentTypeError(
                    f"descending seed range is not supported: {token}"
                )
            seeds.extend(seed & 0xFFFF_FFFF for seed in range(start, end + 1))
        else:
            seeds.append(parse_one(token) & 0xFFFF_FFFF)
    if not seeds:
        raise argparse.ArgumentTypeError("at least one seed is required")
    return seeds


def duplicate_seed_errors(seeds: list[int]) -> list[dict[str, Any]]:
    counts: dict[int, int] = {}
    for seed in seeds:
        counts[seed] = counts.get(seed, 0) + 1
    return [
        {
            "kind": "duplicate_input_seed",
            "requested_seed": f"{seed:08x}",
            "count": count,
        }
        for seed, count in sorted(counts.items())
        if count != 1
    ]


def command_text(command: Iterable[str]) -> str:
    return shlex.join(str(part) for part in command)


def run_command(
    command: list[str],
    *,
    cwd: Path,
    log_path: Path,
    timeout_seconds: int,
) -> tuple[int, str, float]:
    start = time.monotonic()
    try:
        completed = subprocess.run(
            command,
            cwd=cwd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout_seconds,
            check=False,
        )
        output = completed.stdout
        return_code = completed.returncode
    except subprocess.TimeoutExpired as exc:
        partial = exc.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode(errors="replace")
        output = partial + (
            f"\n[RUNNER_TIMEOUT] command exceeded {timeout_seconds} seconds\n"
        )
        return_code = 124

    duration = time.monotonic() - start
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(
        f"[COMMAND] {command_text(command)}\n{output}",
        encoding="utf-8",
    )
    return return_code, output, duration


def parse_d5_results(output: str) -> list[dict[str, str]]:
    results: list[dict[str, str]] = []
    for line in output.splitlines():
        if not line.startswith("[D5_RESULT]"):
            continue
        parsed: dict[str, str] = {}
        for token in line.split()[1:]:
            if "=" not in token:
                continue
            key, value = token.split("=", 1)
            parsed[key] = value
        results.append(parsed)
    return results


def parse_d5_result(output: str) -> dict[str, str]:
    """Return the last result for compatibility; campaign code checks cardinality."""
    results = parse_d5_results(output)
    return results[-1] if results else {}


def validate_run_result(
    parsed_results: list[dict[str, str]],
    requested_seed: str,
    max_stall: int,
) -> tuple[dict[str, str], list[str]]:
    parsed = parsed_results[-1] if parsed_results else {}
    validation_errors: list[str] = []

    if not parsed_results:
        validation_errors.append("missing_d5_result")
    elif len(parsed_results) != 1:
        validation_errors.append(
            f"duplicate_d5_results={len(parsed_results)}_expected_1"
        )

    missing_fields = [field for field in D5_REQUIRED_FIELDS if field not in parsed]
    if missing_fields:
        validation_errors.append(
            "missing_required_fields=" + ",".join(missing_fields)
        )

    reported_status = parsed.get("status")
    if reported_status is not None and reported_status not in ("PASS", "FAIL"):
        validation_errors.append(f"invalid_status={reported_status}")

    reported_seed = parsed.get("seed")
    if reported_seed is None:
        validation_errors.append("missing_reported_seed")
    elif reported_seed != requested_seed:
        validation_errors.append(
            f"reported_seed={reported_seed}_expected_{requested_seed}"
        )

    decimal_values: dict[str, int] = {}
    for field in D5_DECIMAL_FIELDS:
        if field not in parsed:
            continue
        try:
            value = int(parsed[field], 10)
        except ValueError:
            validation_errors.append(f"invalid_decimal_{field}={parsed[field]}")
            continue
        if value < 0:
            validation_errors.append(f"negative_{field}={value}")
            continue
        if field in ("cycles", "checks") and value == 0:
            validation_errors.append(f"nonpositive_{field}=0")
            continue
        decimal_values[field] = value

    for field in D5_HEX_FIELDS:
        if field not in parsed:
            continue
        try:
            value = int(parsed[field], 16)
        except ValueError:
            validation_errors.append(f"invalid_hex_{field}={parsed[field]}")
            continue
        limit = 0xFFFF if field == "coverage" else 0xFFFF_FFFF
        if value < 0 or value > limit:
            validation_errors.append(f"out_of_range_{field}={parsed[field]}")

    for field, expected in D5_ORACLE.items():
        if field in decimal_values and decimal_values[field] != expected:
            validation_errors.append(
                f"oracle_{field}={decimal_values[field]}_expected_{expected}"
            )

    for field in (
        "imem_req_max",
        "imem_rsp_max",
        "dmem_req_max",
        "dmem_rsp_max",
    ):
        if field not in decimal_values:
            continue
        observed_max = decimal_values[field]
        if max_stall == 0:
            if observed_max != 0:
                validation_errors.append(f"{field}={observed_max}_expected_zero")
        elif observed_max > max_stall:
            validation_errors.append(
                f"{field}={observed_max}_exceeds_{max_stall}"
            )
    return parsed, validation_errors


def validate_result_matrix(
    rows: list[dict[str, Any]],
    simulators: list[str],
    requested_seeds: list[str],
) -> list[dict[str, Any]]:
    expected = {
        (simulator, requested_seed)
        for simulator in simulators
        for requested_seed in requested_seeds
    }
    indices_by_key: dict[tuple[str, str], list[int]] = {}
    for index, row in enumerate(rows):
        key = (str(row.get("sim", "")), str(row.get("requested_seed", "")))
        indices_by_key.setdefault(key, []).append(index)

    errors: list[dict[str, Any]] = []
    for simulator, requested_seed in sorted(expected):
        indices = indices_by_key.get((simulator, requested_seed), [])
        if not indices:
            errors.append(
                {
                    "kind": "missing_result",
                    "sim": simulator,
                    "requested_seed": requested_seed,
                    "count": 0,
                }
            )
        elif len(indices) != 1:
            errors.append(
                {
                    "kind": "duplicate_result",
                    "sim": simulator,
                    "requested_seed": requested_seed,
                    "count": len(indices),
                    "row_indices": indices,
                }
            )

    for key, indices in sorted(indices_by_key.items()):
        if key not in expected:
            errors.append(
                {
                    "kind": "unexpected_result",
                    "sim": key[0],
                    "requested_seed": key[1],
                    "count": len(indices),
                    "row_indices": indices,
                }
            )
    return errors


def compare_cross_sim_rows(
    left: dict[str, Any], right: dict[str, Any]
) -> dict[str, tuple[Any, Any]]:
    mismatch = {
        field: (left.get(field), right.get(field))
        for field in D5_COMPARE_FIELDS
        if left.get(field) != right.get(field)
    }
    if left.get("status") != "PASS" or right.get("status") != "PASS":
        mismatch["validated_status"] = (
            left.get("status"),
            right.get("status"),
        )
    return mismatch


def capture_text(command: list[str]) -> str:
    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return completed.stdout.strip()


def input_manifest() -> dict[str, str]:
    paths: set[Path] = set()
    for pattern in (
        "rtl/*.sv",
        "filelists/*.f",
        "tb/core/*.sv",
        "tb/core/*.f",
        "scripts/run_random_regression.py",
        "docs/design/05_random_regression.md",
    ):
        paths.update(ROOT.glob(pattern))

    manifest: dict[str, str] = {}
    for path in sorted(paths):
        relative = path.relative_to(ROOT).as_posix()
        manifest[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    return manifest


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(f"{path.suffix}.tmp")
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def begin_summary(path: Path, results_root: Path, created_utc: str) -> str:
    run_id = uuid.uuid4().hex
    write_json(
        path,
        {
            "status": "running",
            "run_id": run_id,
            "created_utc": created_utc,
            "results_root": str(results_root),
        },
    )
    return run_id


def compile_icarus(build_dir: Path, timeout_seconds: int) -> Path:
    output = build_dir / "tb_rv32_core.vvp"
    command = [
        "iverilog",
        "-g2012",
        "-s",
        "tb_rv32_core",
        "-o",
        str(output),
        "-f",
        "filelists/rv32_core_rtl.f",
        "-f",
        "tb/core/rv32_core_tb.f",
    ]
    return_code, _, _ = run_command(
        command,
        cwd=ROOT,
        log_path=build_dir / "compile.log",
        timeout_seconds=timeout_seconds,
    )
    if return_code != 0:
        raise RuntimeError(
            f"Icarus compile failed; see {build_dir / 'compile.log'}"
        )
    return output


def compile_verilator(build_dir: Path, timeout_seconds: int) -> Path:
    mdir = build_dir / "obj"
    command = [
        "verilator",
        "--binary",
        "--timing",
        "--trace",
        "-Wall",
        "-Wno-TIMESCALEMOD",
        "-Wno-DECLFILENAME",
        "-Wno-UNUSEDSIGNAL",
        "-Wno-UNUSEDPARAM",
        "-Wno-UNSIGNED",
        "-Wno-BLKSEQ",
        "--Mdir",
        str(mdir),
        "--top-module",
        "tb_rv32_core",
        "-f",
        "filelists/rv32_core_rtl.f",
        "-f",
        "tb/core/rv32_core_tb.f",
    ]
    return_code, _, _ = run_command(
        command,
        cwd=ROOT,
        log_path=build_dir / "compile.log",
        timeout_seconds=timeout_seconds,
    )
    if return_code != 0:
        raise RuntimeError(
            f"Verilator compile failed; see {build_dir / 'compile.log'}"
        )
    return mdir / "Vtb_rv32_core"


def simulator_command(simulator: str, executable: Path) -> list[str]:
    if simulator == "icarus":
        return ["vvp", str(executable)]
    return [str(executable)]


def write_replay_script(path: Path, command: list[str]) -> None:
    body = "\n".join(
        (
            "#!/usr/bin/env bash",
            "set -euo pipefail",
            f"cd {shlex.quote(str(ROOT))}",
            command_text(command),
            "",
        )
    )
    path.write_text(body, encoding="utf-8")
    path.chmod(0o755)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="D5 reproducible random-backpressure regression"
    )
    parser.add_argument(
        "--sim",
        choices=("icarus", "verilator", "both"),
        default="both",
        help="simulator campaign to run",
    )
    parser.add_argument(
        "--seeds",
        type=parse_seeds,
        default=parse_seeds("1,7,42,20260727"),
        help="comma-separated seeds or inclusive ranges such as 1..64",
    )
    parser.add_argument("--stall-pct", type=int, default=50)
    parser.add_argument("--max-stall", type=int, default=8)
    parser.add_argument("--timeout-cycles", type=int, default=10000)
    parser.add_argument("--command-timeout", type=int, default=180)
    parser.add_argument(
        "--results-root",
        type=Path,
        help="artifact directory; defaults to out/d5/<UTC timestamp>",
    )
    parser.add_argument(
        "--no-failure-replay",
        action="store_true",
        help="do not rerun the first failing seed with TRACE and DUMP",
    )
    args = parser.parse_args()

    if not 0 <= args.stall_pct <= 100:
        parser.error("--stall-pct must be in the range 0..100")
    if not 0 <= args.max_stall <= 1024:
        parser.error("--max-stall must be in the range 0..1024")
    if args.timeout_cycles <= 0:
        parser.error("--timeout-cycles must be greater than zero")
    if args.command_timeout <= 0:
        parser.error("--command-timeout must be greater than zero")

    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    results_root = (
        args.results_root.resolve()
        if args.results_root
        else ROOT / "out" / "d5" / timestamp
    )
    results_root.mkdir(parents=True, exist_ok=True)
    run_id = begin_summary(
        results_root / "summary.json", results_root, timestamp
    )

    input_seed_errors = duplicate_seed_errors(args.seeds)
    if input_seed_errors:
        aggregate = {
            "status": "FAIL",
            "run_id": run_id,
            "run_count": 0,
            "pass_count": 0,
            "fail_count": 0,
            "result_integrity_errors": input_seed_errors,
            "results_root": str(results_root),
        }
        write_json(results_root / "summary.json", aggregate)
        duplicates = ", ".join(
            error["requested_seed"] for error in input_seed_errors
        )
        print(f"[FAIL] duplicate input seed(s): {duplicates}", file=sys.stderr)
        return 1

    simulators = (
        ["icarus", "verilator"] if args.sim == "both" else [args.sim]
    )
    required_tools = {"icarus": ("iverilog", "vvp"), "verilator": ("verilator",)}
    for simulator in simulators:
        for tool in required_tools[simulator]:
            if shutil.which(tool) is None:
                message = f"required tool not found: {tool}"
                write_json(
                    results_root / "summary.json",
                    {"status": "FAIL", "run_id": run_id, "error": message},
                )
                print(f"[FAIL] {message}", file=sys.stderr)
                return 1

    config = {
        "created_utc": timestamp,
        "run_id": run_id,
        "project_root": str(ROOT),
        "simulators": simulators,
        "seeds": [f"{seed:08x}" for seed in args.seeds],
        "stall_percent": args.stall_pct,
        "max_stall_cycles": args.max_stall,
        "timeout_cycles": args.timeout_cycles,
        "git_head": capture_text(["git", "rev-parse", "HEAD"]),
        "git_status_short": capture_text(["git", "status", "--short"]),
        "tool_versions": {
            "iverilog": capture_text(["iverilog", "-V"]).splitlines()[:1]
            if shutil.which("iverilog")
            else [],
            "verilator": capture_text(["verilator", "--version"])
            if shutil.which("verilator")
            else "",
            "python": sys.version,
        },
        "input_sha256": input_manifest(),
    }
    write_json(results_root / "config.json", config)

    executables: dict[str, Path] = {}
    try:
        for simulator in simulators:
            build_dir = results_root / "build" / simulator
            build_dir.mkdir(parents=True, exist_ok=True)
            print(f"[INFO] compiling {simulator}")
            if simulator == "icarus":
                executables[simulator] = compile_icarus(
                    build_dir, args.command_timeout
                )
            else:
                executables[simulator] = compile_verilator(
                    build_dir, args.command_timeout
                )
    except RuntimeError as exc:
        write_json(
            results_root / "summary.json",
            {"status": "FAIL", "run_id": run_id, "error": str(exc)},
        )
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 1

    rows: list[dict[str, Any]] = []
    first_failure_replayed = False
    for simulator in simulators:
        base_command = simulator_command(simulator, executables[simulator])
        for seed in args.seeds:
            requested_seed = f"{seed:08x}"
            run_dir = (
                results_root
                / "runs"
                / simulator
                / f"seed_{requested_seed}"
            )
            run_dir.mkdir(parents=True, exist_ok=True)
            plusargs = [
                "+D5_ONLY",
                f"+SEED={requested_seed}",
                f"+STALL_PCT={args.stall_pct}",
                f"+MAX_STALL={args.max_stall}",
                f"+TIMEOUT={args.timeout_cycles}",
            ]
            command = base_command + plusargs
            return_code, output, duration = run_command(
                command,
                cwd=ROOT,
                log_path=run_dir / "run.log",
                timeout_seconds=args.command_timeout,
            )
            parsed_results = parse_d5_results(output)
            parsed, validation_errors = validate_run_result(
                parsed_results, requested_seed, args.max_stall
            )

            passed = (
                return_code == 0
                and parsed.get("status") == "PASS"
                and not validation_errors
            )
            row: dict[str, Any] = {
                **parsed,
                "sim": simulator,
                "run_id": run_id,
                "seed": requested_seed,
                "requested_seed": requested_seed,
                "reported_seed": parsed.get("seed", ""),
                "reported_status": parsed.get("status", ""),
                "status": "PASS" if passed else "FAIL",
                "return_code": return_code,
                "duration_seconds": round(duration, 6),
                "log": str((run_dir / "run.log").relative_to(results_root)),
            }
            if validation_errors:
                row["validation_errors"] = ";".join(validation_errors)
            rows.append(row)
            print(
                f"[{'PASS' if passed else 'FAIL'}] {simulator} "
                f"seed={requested_seed} "
                f"cycles={parsed.get('cycles', '?')} coverage={parsed.get('coverage', '?')}"
            )

            if (
                not passed
                and not args.no_failure_replay
                and not first_failure_replayed
            ):
                first_failure_replayed = True
                wave_path = (run_dir / "failure.vcd").resolve()
                replay_command = command + ["+TRACE", f"+DUMP={wave_path}"]
                write_replay_script(run_dir / "replay.sh", replay_command)
                replay_code, _, _ = run_command(
                    replay_command,
                    cwd=ROOT,
                    log_path=run_dir / "replay.log",
                    timeout_seconds=args.command_timeout,
                )
                row["replay_return_code"] = replay_code
                row["replay_log"] = str(
                    (run_dir / "replay.log").relative_to(results_root)
                )
                row["wave"] = str(wave_path.relative_to(results_root))

    requested_seed_hexes = [f"{seed:08x}" for seed in args.seeds]
    result_integrity_errors = validate_result_matrix(
        rows, simulators, requested_seed_hexes
    )
    for error in result_integrity_errors:
        if error["kind"] == "missing_result":
            continue
        for row in rows:
            if (
                row.get("sim") == error["sim"]
                and row.get("requested_seed") == error["requested_seed"]
            ):
                row["status"] = "FAIL"
                marker = f"result_matrix_{error['kind']}"
                existing = str(row.get("validation_errors", ""))
                row["validation_errors"] = (
                    f"{existing};{marker}" if existing else marker
                )

    cross_sim_mismatches: list[dict[str, Any]] = []
    if len(simulators) == 2 and not result_integrity_errors:
        by_key = {
            (row["sim"], row["requested_seed"]): row for row in rows
        }
        for requested_seed in requested_seed_hexes:
            left = by_key[("icarus", requested_seed)]
            right = by_key[("verilator", requested_seed)]
            mismatch = compare_cross_sim_rows(left, right)
            matched = not mismatch
            left["cross_sim_match"] = matched
            right["cross_sim_match"] = matched
            if mismatch:
                cross_sim_mismatches.append(
                    {"requested_seed": requested_seed, "fields": mismatch}
                )
                left["status"] = "FAIL"
                right["status"] = "FAIL"

    with (results_root / "summary.jsonl").open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True) + "\n")

    csv_fields = sorted({key for row in rows for key in row})
    with (results_root / "summary.csv").open(
        "w", encoding="utf-8", newline=""
    ) as handle:
        writer = csv.DictWriter(handle, fieldnames=csv_fields)
        writer.writeheader()
        writer.writerows(rows)

    required_coverage = 0x03FF
    aggregate_coverage: dict[str, str] = {}
    coverage_errors: list[str] = []
    for simulator in simulators:
        coverage_value = 0
        for row in rows:
            if row["sim"] != simulator:
                continue
            try:
                coverage_value |= int(str(row.get("coverage", "0")), 16)
            except ValueError:
                coverage_errors.append(
                    f"{simulator}: invalid coverage for seed "
                    f"{row['requested_seed']}"
                )
        aggregate_coverage[simulator] = f"{coverage_value:04x}"
        missing = required_coverage & ~coverage_value
        if missing:
            coverage_errors.append(
                f"{simulator}: aggregate coverage misses 0x{missing:04x}"
            )

    failed_rows = [row for row in rows if row["status"] != "PASS"]
    campaign_failed = bool(
        failed_rows
        or result_integrity_errors
        or cross_sim_mismatches
        or coverage_errors
    )
    aggregate = {
        "status": "FAIL" if campaign_failed else "PASS",
        "run_id": run_id,
        "expected_run_count": len(simulators) * len(requested_seed_hexes),
        "run_count": len(rows),
        "pass_count": len(rows) - len(failed_rows),
        "fail_count": len(failed_rows),
        "required_coverage": f"{required_coverage:04x}",
        "aggregate_coverage": aggregate_coverage,
        "coverage_errors": coverage_errors,
        "result_integrity_errors": result_integrity_errors,
        "cross_sim_mismatches": cross_sim_mismatches,
        "results_root": str(results_root),
    }
    write_json(results_root / "summary.json", aggregate)
    print(
        f"[D5_BATCH] status={aggregate['status']} pass={aggregate['pass_count']} "
        f"fail={aggregate['fail_count']} results={results_root}"
    )
    return 0 if not campaign_failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
