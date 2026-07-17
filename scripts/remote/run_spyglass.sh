#!/usr/bin/env bash

set -euo pipefail

: "${ASIC_REMOTE_HOST:?Set ASIC_REMOTE_HOST to an SSH host or config alias}"
: "${ASIC_REMOTE_ROOT:?Set ASIC_REMOTE_ROOT to the repository path on the remote host}"
: "${ASIC_REMOTE_SPYGLASS_HOME:?Set ASIC_REMOTE_SPYGLASS_HOME to the remote SPYGLASS_HOME}"
: "${ASIC_REMOTE_LICENSE_FILE:?Set ASIC_REMOTE_LICENSE_FILE to the remote license file}"

REMOTE_HOST="${ASIC_REMOTE_HOST}"
REMOTE_ROOT="${ASIC_REMOTE_ROOT}"
REMOTE_SPYGLASS_HOME="${ASIC_REMOTE_SPYGLASS_HOME}"
REMOTE_LICENSE_FILE="${ASIC_REMOTE_LICENSE_FILE}"

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
