#!/bin/bash
# Tear down demo stack: tracing and logging workloads first, Cluster Observability Operator last.
#
# Uninstall scripts live next to this file (same directory as master_uninstall.sh):
#   z_tracing_uninstall.sh, z_logging_uninstall.sh, z_coo_uninstall.sh

set -euo pipefail

_DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for _p in "${_DEMO_DIR}/z_tracing_uninstall.sh" "${_DEMO_DIR}/z_logging_uninstall.sh" "${_DEMO_DIR}/z_coo_uninstall.sh"; do
  if [[ ! -f "${_p}" ]]; then
    echo "Missing expected file: ${_p}" >&2
    exit 1
  fi
done

echo "=== 1. z_tracing_uninstall.sh ==="
bash "${_DEMO_DIR}/z_tracing_uninstall.sh"

echo "=== 2. z_logging_uninstall.sh ==="
bash "${_DEMO_DIR}/z_logging_uninstall.sh"

echo "=== 3. z_coo_uninstall.sh ==="
bash "${_DEMO_DIR}/z_coo_uninstall.sh"

echo "Done (master_uninstall.sh)."
