#!/usr/bin/env python3
"""Build and compare one RV32IM_Zicsr program on Spike and the RTL core."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Any


RESET_VECTOR = 0x8000_0000
DEFAULT_MEMORY_SIZE = 0x4000
ISA = "RV32IM_Zicsr"
MARCH = "rv32im_zicsr"
MABI = "ilp32"
PRIVILEGE = "M"
TB_TOP = "tb_rv32_program"
DUT_RESET_MTVEC = 0x8000_0300
SPIKE_INITIAL_MTVEC = 0x0000_0000

COMMIT_RE = re.compile(
    r"^core\s+\d+:\s+(\d+)\s+(0x[0-9a-fA-F]+)\s+"
    r"\((0x[0-9a-fA-F]+)\)(.*)$"
)
REGISTER_RE = re.compile(r"\bx(\d+)\s+(0x[0-9a-fA-F]+)")
MEMORY_RE = re.compile(
    r"\bmem\s+(0x[0-9a-fA-F]+)(?:\s+(0x[0-9a-fA-F]+))?"
)
EXCEPTION_RE = re.compile(
    r"^core\s+\d+:\s+exception\s+([^,]+),\s+epc\s+(0x[0-9a-fA-F]+)"
)
TVAL_RE = re.compile(r"^core\s+\d+:\s+tval\s+(0x[0-9a-fA-F]+)")

EXCEPTION_CAUSES = {
    "trap_instruction_address_misaligned": 0,
    "trap_instruction_access_fault": 1,
    "trap_illegal_instruction": 2,
    "trap_breakpoint": 3,
    "trap_load_address_misaligned": 4,
    "trap_load_access_fault": 5,
    "trap_store_address_misaligned": 6,
    "trap_store_access_fault": 7,
    "trap_user_ecall": 8,
    "trap_supervisor_ecall": 9,
    "trap_virtual_supervisor_ecall": 10,
    "trap_machine_ecall": 11,
    "trap_instruction_page_fault": 12,
    "trap_load_page_fault": 13,
    "trap_store_page_fault": 15,
}


class DifferentialError(RuntimeError):
    """A setup, tool, trace, or execution error."""


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def atomic_write_json(path: Path, document: dict[str, Any]) -> None:
    """Atomically replace one decisive JSON artifact in its existing directory."""
    file_descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as stream:
            json.dump(document, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def divergence_document(
    *,
    run_id: str,
    started_at: str,
    status: str,
    finished_at: str | None = None,
    divergence: dict[str, Any] | None = None,
    error: str | None = None,
) -> dict[str, Any]:
    document: dict[str, Any] = {
        "format": "rv32-differential-divergence-v1",
        "run_id": run_id,
        "started_at": started_at,
        "finished_at": finished_at,
        "status": status,
        "first_divergence": divergence,
    }
    if divergence is not None:
        document.update(divergence)
    if error is not None:
        document["error"] = error
    return document


def hex32(value: int) -> str:
    return f"0x{value & 0xFFFF_FFFF:08x}"


def integer(text: str) -> int:
    try:
        return int(text, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid integer: {text}") from exc


def find_tool(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise DifferentialError(f"required tool is not on PATH: {name}")
    return path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tool_record(path: str) -> dict[str, str]:
    resolved = Path(path).resolve()
    return {
        "path": path,
        "resolved_path": str(resolved),
        "sha256": sha256_file(resolved),
    }


def input_file_record(path: Path, repo: Path) -> dict[str, str]:
    resolved = path.resolve()
    if not resolved.is_file():
        raise DifferentialError(f"provenance input is not a file: {resolved}")
    try:
        display_path = str(resolved.relative_to(repo.resolve()))
    except ValueError:
        display_path = str(resolved)
    return {
        "path": display_path,
        "resolved_path": str(resolved),
        "sha256": sha256_file(resolved),
    }


def filelist_record(filelist: Path, repo: Path) -> dict[str, Any]:
    sources: list[dict[str, str]] = []
    for line_number, raw_line in enumerate(
        filelist.read_text(encoding="utf-8").splitlines(), start=1
    ):
        line = raw_line.partition("#")[0].partition("//")[0].strip()
        if not line:
            continue
        fields = shlex.split(line)
        if len(fields) != 1 or fields[0].startswith(("-", "+")):
            raise DifferentialError(
                f"unsupported filelist syntax at {filelist}:{line_number}: {raw_line}"
            )
        source = Path(fields[0])
        if not source.is_absolute():
            source = repo / source
        sources.append(input_file_record(source, repo))
    if not sources:
        raise DifferentialError(f"filelist contains no source files: {filelist}")
    return {
        "filelist": input_file_record(filelist, repo),
        "sources": sources,
    }


def git_provenance(repo: Path) -> dict[str, Any]:
    def git(*arguments: str) -> str:
        result = subprocess.run(
            ["git", "-C", str(repo), *arguments],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout).strip()
            raise DifferentialError(
                f"git {' '.join(arguments)} failed with exit code "
                f"{result.returncode}: {detail}"
            )
        return result.stdout.strip()

    head = git("rev-parse", "HEAD")
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    status_lines = git("status", "--porcelain=v1", "--untracked-files=all").splitlines()
    untracked = sum(line.startswith("??") for line in status_lines)
    tracked = len(status_lines) - untracked
    index_changes = sum(
        not line.startswith("??") and len(line) >= 2 and line[0] != " "
        for line in status_lines
    )
    worktree_changes = sum(
        not line.startswith("??") and len(line) >= 2 and line[1] != " "
        for line in status_lines
    )
    return {
        "head": head,
        "branch": branch,
        "dirty": bool(status_lines),
        "status_summary": {
            "entries": len(status_lines),
            "tracked": tracked,
            "untracked": untracked,
            "index_changes": index_changes,
            "worktree_changes": worktree_changes,
        },
        "status_porcelain": status_lines,
    }


def run_command(
    label: str,
    command: list[str],
    cwd: Path,
    artifact_dir: Path,
    timeout: float,
    commands: list[dict[str, Any]],
) -> subprocess.CompletedProcess[str]:
    record: dict[str, Any] = {
        "label": label,
        "cwd": str(cwd),
        "argv": command,
        "shell": shlex.join(command),
    }
    commands.append(record)
    process = subprocess.Popen(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=2.0)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
        (artifact_dir / f"{label}.stdout").write_text(stdout, encoding="utf-8")
        (artifact_dir / f"{label}.stderr").write_text(stderr, encoding="utf-8")
        record["timeout_seconds"] = timeout
        raise DifferentialError(f"{label} timed out after {timeout:g} seconds") from exc

    result = subprocess.CompletedProcess(
        command,
        process.returncode,
        stdout,
        stderr,
    )

    (artifact_dir / f"{label}.stdout").write_text(result.stdout, encoding="utf-8")
    (artifact_dir / f"{label}.stderr").write_text(result.stderr, encoding="utf-8")
    record["returncode"] = result.returncode
    if result.returncode != 0:
        raise DifferentialError(
            f"{label} failed with exit code {result.returncode}; "
            f"see {artifact_dir / f'{label}.stderr'}"
        )
    return result


def read_symbols(nm_output: str) -> dict[str, int]:
    symbols: dict[str, int] = {}
    for line in nm_output.splitlines():
        fields = line.split()
        if len(fields) >= 3:
            try:
                symbols[fields[-1]] = int(fields[0], 16)
            except ValueError:
                continue
    return symbols


def store_format(insn: int, address: int, value: int) -> tuple[int, int]:
    funct3 = (insn >> 12) & 0x7
    sizes = {0: 1, 1: 2, 2: 4}
    if funct3 not in sizes:
        raise DifferentialError(
            f"unsupported store funct3={funct3} in instruction {hex32(insn)}"
        )
    size = sizes[funct3]
    lane = address & 3
    if lane + size > 4:
        raise DifferentialError(
            f"misaligned/cross-word store at {hex32(address)} is outside D5 scope"
        )
    strobe = ((1 << size) - 1) << lane
    value_mask = (1 << (size * 8)) - 1
    shifted_value = ((value & value_mask) << (lane * 8)) & 0xFFFF_FFFF
    return strobe, shifted_value


def parse_spike_log(
    path: Path, reset_vector: int, tohost: int
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    architecture: list[dict[str, Any]] = []
    memory: list[dict[str, Any]] = []
    started = False
    saw_tohost = False
    pending_trap: dict[str, Any] | None = None

    for line_number, line in enumerate(
        path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1
    ):
        exception_match = EXCEPTION_RE.match(line)
        if exception_match:
            pc = int(exception_match.group(2), 16)
            if started or pc == reset_vector:
                started = True
                name = exception_match.group(1)
                if name not in EXCEPTION_CAUSES:
                    raise DifferentialError(
                        f"unsupported Spike exception {name!r} at line {line_number}"
                    )
                pending_trap = {
                    "kind": "trap",
                    "order": len(architecture),
                    "pc": hex32(pc),
                    "cause": hex32(EXCEPTION_CAUSES[name]),
                    "value": hex32(0),
                    "spike_name": name,
                }
            continue

        tval_match = TVAL_RE.match(line)
        if tval_match and pending_trap is not None:
            pending_trap["value"] = hex32(int(tval_match.group(1), 16))
            architecture.append(pending_trap)
            pending_trap = None
            continue

        commit_match = COMMIT_RE.match(line)
        if not commit_match:
            continue

        pc = int(commit_match.group(2), 16)
        insn = int(commit_match.group(3), 16)
        suffix = commit_match.group(4)
        if not started:
            if pc != reset_vector:
                continue
            started = True

        if pending_trap is not None:
            architecture.append(pending_trap)
            pending_trap = None

        register_match = REGISTER_RE.search(suffix)
        rd_addr = int(register_match.group(1)) if register_match else 0
        rd_data = int(register_match.group(2), 16) if register_match else 0
        retire = {
            "kind": "retire",
            "order": len(architecture),
            "pc": hex32(pc),
            "insn": hex32(insn),
            "rd_we": bool(register_match and rd_addr != 0),
            "rd_addr": rd_addr,
            "rd_data": hex32(rd_data),
        }
        architecture.append(retire)

        opcode = insn & 0x7F
        memory_match = MEMORY_RE.search(suffix)
        if opcode in (0x03, 0x23):
            if memory_match is None:
                raise DifferentialError(
                    f"Spike omitted memory metadata at {hex32(pc)} (line {line_number})"
                )
            address = int(memory_match.group(1), 16)
            write = opcode == 0x23
            wstrb = 0
            wdata = 0
            if write:
                if memory_match.group(2) is None:
                    raise DifferentialError(
                        f"Spike omitted store data at {hex32(pc)} (line {line_number})"
                    )
                wstrb, wdata = store_format(
                    insn, address, int(memory_match.group(2), 16)
                )
            memory.append(
                {
                    "kind": "memory",
                    "order": len(memory),
                    "pc": hex32(pc),
                    "insn": hex32(insn),
                    "write": write,
                    "addr": hex32(address),
                    "wdata": hex32(wdata),
                    "wstrb": f"0x{wstrb:x}",
                }
            )
            if write and (address & ~3) == (tohost & ~3):
                saw_tohost = True
                break

    if not started:
        raise DifferentialError(
            f"Spike log never reached reset vector {hex32(reset_vector)}"
        )
    if not saw_tohost:
        raise DifferentialError(
            f"Spike did not commit a store to tohost {hex32(tohost)}"
        )
    return architecture, memory


def read_dut_trace(
    path: Path,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    architecture: list[dict[str, Any]] = []
    memory: list[dict[str, Any]] = []
    summary: dict[str, Any] | None = None
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        try:
            event = json.loads(line)
        except json.JSONDecodeError as exc:
            raise DifferentialError(
                f"invalid DUT JSONL at line {line_number}: {exc}"
            ) from exc
        kind = event.get("kind")
        if kind in ("retire", "trap"):
            architecture.append(event)
        elif kind == "memory":
            memory.append(event)
        elif kind == "summary":
            summary = event
    if summary is None:
        raise DifferentialError("DUT trace has no summary event")
    if summary.get("status") != "pass":
        raise DifferentialError(f"DUT did not pass: {summary}")
    return architecture, memory, summary


def trap_free_violation(
    spike_architecture: list[dict[str, Any]],
    dut_architecture: list[dict[str, Any]],
    dut_summary: dict[str, Any],
) -> dict[str, Any] | None:
    """Reject traps before comparison because Spike/DUT mtvec reset differs."""
    spike_traps = [event for event in spike_architecture if event.get("kind") == "trap"]
    dut_traps = [event for event in dut_architecture if event.get("kind") == "trap"]
    summary_traps = dut_summary.get("traps")
    if not spike_traps and not dut_traps and summary_traps == 0:
        return None

    return {
        "stream": "trap-free-profile",
        "index": 0,
        "reason": (
            "trap-free differential profile violated: "
            f"Spike trace traps={len(spike_traps)}, "
            f"DUT trace traps={len(dut_traps)}, "
            f"DUT summary traps={summary_traps!r}"
        ),
        "spike": spike_traps[0] if spike_traps else None,
        "dut": dut_traps[0] if dut_traps else dut_summary,
        "context": {
            "spike_traps": spike_traps[:3],
            "dut_traps": dut_traps[:3],
            "dut_summary": dut_summary,
        },
    }


def event_difference(
    spike: dict[str, Any], dut: dict[str, Any], stream: str
) -> str | None:
    if spike.get("kind") != dut.get("kind"):
        return f"{stream} kind differs"
    kind = spike["kind"]
    fields: list[str]
    if kind == "retire":
        fields = ["pc", "insn", "rd_we"]
        if spike.get("rd_we") or dut.get("rd_we"):
            fields.extend(["rd_addr", "rd_data"])
    elif kind == "trap":
        fields = ["pc", "cause", "value"]
    elif kind == "memory":
        fields = ["pc", "insn", "write", "addr"]
        if spike.get("write") or dut.get("write"):
            fields.extend(["wstrb", "wdata"])
    else:
        return f"unsupported {stream} event kind {kind!r}"

    for field in fields:
        if spike.get(field) != dut.get(field):
            return (
                f"{stream} {field} differs: "
                f"Spike={spike.get(field)!r}, DUT={dut.get(field)!r}"
            )
    return None


def compare_stream(
    name: str,
    spike_events: list[dict[str, Any]],
    dut_events: list[dict[str, Any]],
) -> dict[str, Any] | None:
    common = min(len(spike_events), len(dut_events))
    for index in range(common):
        reason = event_difference(spike_events[index], dut_events[index], name)
        if reason is not None:
            start = max(0, index - 2)
            end = index + 3
            return {
                "stream": name,
                "index": index,
                "reason": reason,
                "spike": spike_events[index],
                "dut": dut_events[index],
                "context": {
                    "spike": spike_events[start:end],
                    "dut": dut_events[start:end],
                },
            }
    if len(spike_events) != len(dut_events):
        index = common
        return {
            "stream": name,
            "index": index,
            "reason": (
                f"{name} length differs: Spike={len(spike_events)}, "
                f"DUT={len(dut_events)}"
            ),
            "spike": spike_events[index] if index < len(spike_events) else None,
            "dut": dut_events[index] if index < len(dut_events) else None,
            "context": {
                "spike": spike_events[max(0, index - 2) : index + 3],
                "dut": dut_events[max(0, index - 2) : index + 3],
            },
        }
    return None


def write_jsonl(
    path: Path,
    architecture: list[dict[str, Any]],
    memory: list[dict[str, Any]],
) -> None:
    events = architecture + memory
    with path.open("w", encoding="utf-8") as stream:
        for event in events:
            stream.write(json.dumps(event, sort_keys=True) + "\n")
        stream.write(
            json.dumps(
                {
                    "kind": "summary",
                    "status": "tohost",
                    "architectural_events": len(architecture),
                    "memory_events": len(memory),
                },
                sort_keys=True,
            )
            + "\n"
        )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--elf", type=Path, help="use an already linked ELF")
    parser.add_argument(
        "--program",
        type=Path,
        help="assembly/C source to build (default: tb/program/smoke.S)",
    )
    parser.add_argument("--linker", type=Path, help="linker script override")
    parser.add_argument("--build-dir", type=Path, help="artifact directory")
    parser.add_argument(
        "--memory-size",
        type=integer,
        default=DEFAULT_MEMORY_SIZE,
        help="shared memory bytes, a 4 KiB multiple (default: 0x4000)",
    )
    parser.add_argument("--max-cycles", type=integer, default=20_000)
    parser.add_argument(
        "--timeout",
        type=float,
        default=30.0,
        help="non-RTL-compile command timeout in seconds (default: 30)",
    )
    parser.add_argument(
        "--compile-timeout",
        type=float,
        default=180.0,
        help="RTL compile timeout in seconds (default: 180)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    repo = Path(__file__).resolve().parent.parent
    artifact_dir = (
        args.build_dir.resolve()
        if args.build_dir
        else Path(tempfile.mkdtemp(prefix="rv32-differential."))
    )
    artifact_dir.mkdir(parents=True, exist_ok=True)
    commands: list[dict[str, Any]] = []
    run_id = uuid.uuid4().hex
    started_at = utc_now()
    finished_at: str | None = None
    comparison_path = artifact_dir / "comparison.json"
    divergence_path = artifact_dir / "first_divergence.json"
    manifest_path = artifact_dir / "manifest.json"

    parameters = {
        "reset_vector": hex32(RESET_VECTOR),
        "memory_size": args.memory_size,
        "isa": ISA,
        "march": MARCH,
        "mabi": MABI,
        "privilege": PRIVILEGE,
        "tb_top": TB_TOP,
        "trap_policy": "trap-free",
        "dut_reset_mtvec": hex32(DUT_RESET_MTVEC),
        "spike_initial_mtvec": hex32(SPIKE_INITIAL_MTVEC),
        "max_cycles": args.max_cycles,
        "timeout_seconds": args.timeout,
        "compile_timeout_seconds": args.compile_timeout,
    }
    result_base: dict[str, Any] = {
        "format": "rv32-differential-result-v1",
        "run_id": run_id,
        "artifact_directory": str(artifact_dir),
        "started_at": started_at,
        "parameters": parameters,
    }
    manifest: dict[str, Any] = {
        "format": "rv32-differential-manifest-v1",
        "run_id": run_id,
        "started_at": started_at,
        "finished_at": None,
        "status": "running",
        "artifact_directory": str(artifact_dir),
        "parameters": parameters,
        "commands": commands,
    }

    try:
        # The first atomic replacement is deliberately comparison.json: once
        # this succeeds, a PASS from an earlier use of --build-dir cannot be
        # mistaken for the current invocation, even if this process is killed.
        atomic_write_json(
            comparison_path,
            {
                **result_base,
                "finished_at": None,
                "status": "running",
                "first_divergence": None,
            },
        )
        atomic_write_json(
            divergence_path,
            divergence_document(
                run_id=run_id,
                started_at=started_at,
                status="pending",
            ),
        )
        atomic_write_json(manifest_path, manifest)

        if args.max_cycles <= 0:
            raise DifferentialError("--max-cycles must be positive")
        if args.timeout <= 0:
            raise DifferentialError("--timeout must be positive")
        if args.compile_timeout <= 0:
            raise DifferentialError("--compile-timeout must be positive")
        if args.memory_size < 0x1000 or args.memory_size % 0x1000 != 0:
            raise DifferentialError(
                "--memory-size must be a positive 4 KiB multiple"
            )
        if RESET_VECTOR + args.memory_size > 0x1_0000_0000:
            raise DifferentialError("--memory-size exceeds the 32-bit address space")

        manifest["git"] = git_provenance(repo)
        manifest["inputs"] = {
            "runner": input_file_record(Path(__file__), repo),
            "elf_to_mem": input_file_record(repo / "scripts/elf_to_mem.py", repo),
            "rtl": filelist_record(repo / "filelists/rv32_core_rtl.f", repo),
            "program_tb": filelist_record(
                repo / "tb/program/rv32_program_tb.f",
                repo,
            ),
        }

        tool_paths = {
            "python": sys.executable,
            "cc": find_tool("riscv64-unknown-elf-gcc"),
            "nm": find_tool("riscv64-unknown-elf-nm"),
            "spike": find_tool("spike"),
            "iverilog": find_tool("iverilog"),
            "vvp": find_tool("vvp"),
        }
        manifest["tools"] = {
            name: tool_record(path) for name, path in tool_paths.items()
        }

        if args.elf is not None:
            elf_path = args.elf.resolve()
            if not elf_path.is_file():
                raise DifferentialError(f"ELF does not exist: {elf_path}")
            manifest["inputs"]["provided_elf"] = input_file_record(elf_path, repo)
        else:
            program = (
                args.program.resolve()
                if args.program
                else repo / "tb/program/smoke.S"
            )
            linker = (
                args.linker.resolve()
                if args.linker
                else repo / "tb/program/link.ld"
            )
            if not program.is_file():
                raise DifferentialError(f"program source does not exist: {program}")
            if not linker.is_file():
                raise DifferentialError(f"linker script does not exist: {linker}")
            manifest["inputs"]["program"] = input_file_record(program, repo)
            manifest["inputs"]["linker"] = input_file_record(linker, repo)
            elf_path = artifact_dir / "program.elf"
            map_path = artifact_dir / "program.map"
            run_command(
                "build_elf",
                [
                    tool_paths["cc"],
                    f"-march={MARCH}",
                    f"-mabi={MABI}",
                    "-nostdlib",
                    "-nostartfiles",
                    "-ffreestanding",
                    "-Wl,--no-relax",
                    f"-Wl,-T,{linker}",
                    f"-Wl,-Map,{map_path}",
                    "-o",
                    str(elf_path),
                    str(program),
                ],
                repo,
                artifact_dir,
                args.timeout,
                commands,
            )
            manifest["program"] = str(program)
            manifest["linker"] = str(linker)

        elf_sha256 = sha256_file(elf_path.resolve())
        manifest["elf"] = str(elf_path)
        manifest["elf_sha256"] = elf_sha256
        manifest["artifacts"] = {
            "elf": input_file_record(elf_path, repo),
        }
        nm_result = run_command(
            "symbols",
            [tool_paths["nm"], "-n", str(elf_path)],
            repo,
            artifact_dir,
            args.timeout,
            commands,
        )
        symbols = read_symbols(nm_result.stdout)
        if symbols.get("_start") != RESET_VECTOR:
            actual = symbols.get("_start")
            actual_text = "missing" if actual is None else hex32(actual)
            raise DifferentialError(
                f"_start must equal {hex32(RESET_VECTOR)}, found {actual_text}"
            )
        if "tohost" not in symbols:
            raise DifferentialError("ELF must define a tohost symbol")
        tohost = symbols["tohost"]
        if not RESET_VECTOR <= tohost < RESET_VECTOR + args.memory_size:
            raise DifferentialError(
                f"tohost {hex32(tohost)} lies outside the shared memory window"
            )
        manifest["symbols"] = {
            "_start": hex32(symbols["_start"]),
            "tohost": hex32(tohost),
        }

        mem_hex = artifact_dir / "program.hex"
        image_metadata = artifact_dir / "image.json"
        run_command(
            "elf_to_mem",
            [
                tool_paths["python"],
                str(repo / "scripts/elf_to_mem.py"),
                str(elf_path),
                "-o",
                str(mem_hex),
                "--base",
                hex(RESET_VECTOR),
                "--size",
                hex(args.memory_size),
                "--metadata",
                str(image_metadata),
            ],
            repo,
            artifact_dir,
            args.timeout,
            commands,
        )
        manifest["artifacts"]["program_hex"] = input_file_record(mem_hex, repo)
        manifest["artifacts"]["image_metadata"] = input_file_record(
            image_metadata,
            repo,
        )

        simulation = artifact_dir / "tb_rv32_program.vvp"
        run_command(
            "compile_rtl",
            [
                tool_paths["iverilog"],
                "-g2012",
                "-s",
                TB_TOP,
                f"-P{TB_TOP}.MEM_BYTES={args.memory_size}",
                f"-P{TB_TOP}.MTVEC_RESET={DUT_RESET_MTVEC}",
                "-o",
                str(simulation),
                "-f",
                "filelists/rv32_core_rtl.f",
                "-f",
                "tb/program/rv32_program_tb.f",
            ],
            repo,
            artifact_dir,
            args.compile_timeout,
            commands,
        )
        manifest["artifacts"]["tb_rv32_program_vvp"] = input_file_record(
            simulation,
            repo,
        )

        dut_trace = artifact_dir / "dut.jsonl"
        run_command(
            "run_dut",
            [
                tool_paths["vvp"],
                str(simulation),
                f"+MEM_HEX={mem_hex}",
                f"+TRACE={dut_trace}",
                f"+TOHOST={tohost:08x}",
                f"+MAX_CYCLES={args.max_cycles}",
            ],
            repo,
            artifact_dir,
            args.timeout,
            commands,
        )

        spike_log = artifact_dir / "spike.log"
        run_command(
            "run_spike",
            [
                tool_paths["spike"],
                f"--isa={ISA}",
                f"--priv={PRIVILEGE}",
                f"--pc={hex(RESET_VECTOR)}",
                f"-m{hex(RESET_VECTOR)}:{hex(args.memory_size)}",
                f"--instructions={args.max_cycles}",
                "-l",
                "--log-commits",
                f"--log={spike_log}",
                str(elf_path),
            ],
            repo,
            artifact_dir,
            args.timeout,
            commands,
        )

        spike_arch, spike_memory = parse_spike_log(
            spike_log, RESET_VECTOR, tohost
        )
        dut_arch, dut_memory, dut_summary = read_dut_trace(dut_trace)
        normalized_spike = artifact_dir / "spike.jsonl"
        write_jsonl(normalized_spike, spike_arch, spike_memory)

        divergence = trap_free_violation(spike_arch, dut_arch, dut_summary)
        if divergence is None:
            divergence = compare_stream("architecture", spike_arch, dut_arch)
        if divergence is None:
            divergence = compare_stream("memory", spike_memory, dut_memory)

        finished_at = utc_now()
        comparison = {
            **result_base,
            "finished_at": finished_at,
            "status": "mismatch" if divergence else "pass",
            "elf": str(elf_path),
            "elf_sha256": elf_sha256,
            "spike": {
                "architectural_events": len(spike_arch),
                "memory_events": len(spike_memory),
            },
            "dut": {
                "architectural_events": len(dut_arch),
                "memory_events": len(dut_memory),
                "summary": dut_summary,
            },
            "first_divergence": divergence,
        }
        if divergence is not None:
            atomic_write_json(
                divergence_path,
                divergence_document(
                    run_id=run_id,
                    started_at=started_at,
                    finished_at=finished_at,
                    status="mismatch",
                    divergence=divergence,
                ),
            )
            atomic_write_json(comparison_path, comparison)
            manifest["status"] = "mismatch"
            print(f"[FAIL] first divergence: {divergence['reason']}", file=sys.stderr)
            print(f"artifacts: {artifact_dir}", file=sys.stderr)
            return 1

        atomic_write_json(
            divergence_path,
            divergence_document(
                run_id=run_id,
                started_at=started_at,
                finished_at=finished_at,
                status="none",
            ),
        )
        atomic_write_json(comparison_path, comparison)
        manifest["status"] = "pass"
        print(
            "[PASS] RV32 differential: "
            f"{len(dut_arch)} architectural events, "
            f"{len(dut_memory)} memory events"
        )
        print(f"artifacts: {artifact_dir}")
        return 0
    except Exception as exc:
        finished_at = utc_now()
        manifest["status"] = "error"
        manifest["error"] = str(exc)
        error_comparison = {
            **result_base,
            "finished_at": finished_at,
            "status": "error",
            "error": str(exc),
            "first_divergence": None,
        }
        try:
            atomic_write_json(
                divergence_path,
                divergence_document(
                    run_id=run_id,
                    started_at=started_at,
                    finished_at=finished_at,
                    status="error",
                    error=str(exc),
                ),
            )
            atomic_write_json(comparison_path, error_comparison)
        except OSError as publish_error:
            manifest["result_publish_error"] = str(publish_error)
            print(
                f"run_differential.py: could not publish error result: {publish_error}",
                file=sys.stderr,
            )
        print(f"run_differential.py: error: {exc}", file=sys.stderr)
        print(f"artifacts: {artifact_dir}", file=sys.stderr)
        return 2
    finally:
        if finished_at is None:
            finished_at = utc_now()
        manifest["finished_at"] = finished_at
        atomic_write_json(manifest_path, manifest)


if __name__ == "__main__":
    raise SystemExit(main())
