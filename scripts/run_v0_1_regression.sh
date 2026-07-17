#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUN_VERILATOR=1

if [[ "${1:-}" == "--icarus-only" ]]; then
    RUN_VERILATOR=0
elif [[ -n "${1:-}" ]]; then
    echo "Usage: $0 [--icarus-only]" >&2
    exit 2
fi

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[ERROR] Required tool not found: $1" >&2
        exit 1
    fi
}

require_tool iverilog
require_tool vvp
if [[ "${RUN_VERILATOR}" -eq 1 ]]; then
    require_tool verilator
fi

if [[ -n "${BUILD_ROOT:-}" ]]; then
    mkdir -p "${BUILD_ROOT}"
else
    BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rv32-v01-regression.XXXXXX")"
fi

cd "${ROOT_DIR}"

echo "[INFO] Project root: ${ROOT_DIR}"
echo "[INFO] Build root:   ${BUILD_ROOT}"
echo "[INFO] $(iverilog -V 2>&1 | head -n 1)"
if [[ "${RUN_VERILATOR}" -eq 1 ]]; then
    echo "[INFO] $(verilator --version)"
fi

run_icarus_test() {
    local top="$1"
    local source="$2"
    local compile_log="${BUILD_ROOT}/${top}.compile.log"
    local run_log="${BUILD_ROOT}/${top}.run.log"
    local output="${BUILD_ROOT}/${top}.vvp"
    local summary

    if ! iverilog -g2012 -s "${top}" -o "${output}" \
        -f filelists/rv32_core_rtl.f "${source}" \
        >"${compile_log}" 2>&1; then
        echo "[FAIL] ${top}: compile failed" >&2
        tail -n 120 "${compile_log}" >&2
        return 1
    fi

    if ! vvp "${output}" >"${run_log}" 2>&1; then
        echo "[FAIL] ${top}: simulation failed" >&2
        tail -n 160 "${run_log}" >&2
        return 1
    fi

    summary="$(grep -E '\[PASS\]|PASS' "${run_log}" | tail -n 1 || true)"
    echo "[PASS] ${top}: ${summary:-simulation exited successfully}"
}

UNIT_NAMES=(
    alu
    branch_compare
    csr_alu
    csr_trap
    csr_decoder
    decoder
    exu
    forward_unit
    idu
    ifu
    imm_gen
    lsu
    pipeline_ctrl
    regfile
)
unit_count=0
unit_total="${#UNIT_NAMES[@]}"

echo
echo "[INFO] Running Icarus unit regressions"
for name in "${UNIT_NAMES[@]}"; do
    run_icarus_test "tb_rv32_${name}" "tb/unit/tb_rv32_${name}.sv"
    unit_count=$((unit_count + 1))
done

echo
echo "[INFO] Running Icarus core regression"
core_compile_log="${BUILD_ROOT}/tb_rv32_core.compile.log"
core_run_log="${BUILD_ROOT}/tb_rv32_core.run.log"
core_output="${BUILD_ROOT}/tb_rv32_core.vvp"

if ! iverilog -g2012 -s tb_rv32_core -o "${core_output}" \
    -f tb/core/rv32_core.f >"${core_compile_log}" 2>&1; then
    echo "[FAIL] tb_rv32_core: Icarus compile failed" >&2
    tail -n 160 "${core_compile_log}" >&2
    exit 1
fi

if ! vvp "${core_output}" >"${core_run_log}" 2>&1; then
    echo "[FAIL] tb_rv32_core: Icarus simulation failed" >&2
    tail -n 200 "${core_run_log}" >&2
    exit 1
fi
grep -E '\[PASS\] rv32_core' "${core_run_log}" | tail -n 1

if [[ "${RUN_VERILATOR}" -eq 1 ]]; then
    echo
    echo "[INFO] Running Verilator core regression"
    verilator_dir="${BUILD_ROOT}/verilator"
    verilator_build_log="${BUILD_ROOT}/verilator.compile.log"
    verilator_run_log="${BUILD_ROOT}/verilator.run.log"

    if ! verilator --binary --timing -Wall \
        -Wno-TIMESCALEMOD -Wno-DECLFILENAME \
        -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
        -Wno-UNSIGNED -Wno-BLKSEQ \
        --Mdir "${verilator_dir}" \
        --top-module tb_rv32_core \
        -f tb/core/rv32_core.f \
        >"${verilator_build_log}" 2>&1; then
        echo "[FAIL] tb_rv32_core: Verilator build failed" >&2
        tail -n 200 "${verilator_build_log}" >&2
        exit 1
    fi

    if ! "${verilator_dir}/Vtb_rv32_core" \
        >"${verilator_run_log}" 2>&1; then
        echo "[FAIL] tb_rv32_core: Verilator simulation failed" >&2
        tail -n 200 "${verilator_run_log}" >&2
        exit 1
    fi
    grep -E '\[PASS\] rv32_core' "${verilator_run_log}" | tail -n 1
fi

echo
echo "[PASS] v0.1 regression completed: ${unit_count}/${unit_total} unit TBs and core TB passed"
echo "[INFO] Logs retained under ${BUILD_ROOT}"
