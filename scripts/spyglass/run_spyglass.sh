#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SPYGLASS_BIN="${SPYGLASS_BIN:-spyglass}"
LOG_DIR="${REPO_ROOT}/build/spyglass"
LOG_FILE="${LOG_DIR}/lint_rtl.log"

if ! command -v "${SPYGLASS_BIN}" >/dev/null 2>&1; then
    printf 'ERROR: SpyGlass executable not found: %s\n' "${SPYGLASS_BIN}" >&2
    printf 'Load the EDA environment or set SPYGLASS_BIN to its full path.\n' >&2
    exit 127
fi

mkdir -p "${LOG_DIR}"
cd "${REPO_ROOT}"

printf 'Repository : %s\n' "${REPO_ROOT}"
printf 'Executable : %s\n' "$(command -v "${SPYGLASS_BIN}")"
printf 'Goal       : lint/lint_rtl\n'
printf 'Log        : %s\n' "${LOG_FILE}"

set +e
"${SPYGLASS_BIN}" \
    -project scripts/spyglass/rv32_core.prj \
    -goals lint/lint_rtl \
    -batch \
    "$@" \
    2>&1 | tee "${LOG_FILE}"
spyglass_status="${PIPESTATUS[0]}"
set -e

exit "${spyglass_status}"
