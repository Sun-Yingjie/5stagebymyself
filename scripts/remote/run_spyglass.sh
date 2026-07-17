#!/usr/bin/env bash

set -euo pipefail

REMOTE_HOST="${ASIC_REMOTE_HOST:-eda-host}"
REMOTE_ROOT="${ASIC_REMOTE_ROOT:-/path/to/5stagebymyself}"
REMOTE_SPYGLASS_HOME="${ASIC_REMOTE_SPYGLASS_HOME:-/path/to/SPYGLASS_HOME}"
REMOTE_LICENSE_FILE="${ASIC_REMOTE_LICENSE_FILE:-/path/to/Synopsys.dat}"

ssh -o BatchMode=yes "${REMOTE_HOST}" \
    bash -s -- \
    "${REMOTE_ROOT}" \
    "${REMOTE_SPYGLASS_HOME}" \
    "${REMOTE_LICENSE_FILE}" \
    "$@" <<'REMOTE_SCRIPT'
set -euo pipefail

repo_root="$1"
spyglass_home="$2"
license_file="$3"
shift 3

export SPYGLASS_HOME="${spyglass_home}"
export LM_LICENSE_FILE="${license_file}"
export PATH="${SPYGLASS_HOME}/bin:${PATH}"

cd "${repo_root}"
SPYGLASS_BIN="${SPYGLASS_HOME}/bin/spyglass" \
    bash scripts/spyglass/run_spyglass.sh "$@"
REMOTE_SCRIPT
