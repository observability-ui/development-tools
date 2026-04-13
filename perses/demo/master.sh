#!/bin/bash
# Demo orchestration: Cluster Observability Operator + logging + tracing stacks, htpasswd test users, Perses RBAC.
#
# Install scripts live next to this file (same directory as master.sh): z_coo.sh, z_logging.sh, z_tracing.sh
# From this directory, Perses RBAC helpers are under ../rbac/ (sibling of demo/).
#
# Prerequisites: oc (cluster-admin), htpasswd on PATH.
# replace-htpssd-test-user.sh: non-interactive (N = not ROSA, namespace openshift-monitoring).

set -euo pipefail

_DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_UI="${_DEMO_DIR}"
_RBAC="$(cd "${_DEMO_DIR}/../rbac" && pwd)"
_E2E="${_RBAC}/coo140/rbac_perses_e2e_user1_to_user6.sh"

for _p in "${_UI}/z_coo.sh" "${_UI}/z_logging.sh" "${_UI}/z_tracing.sh" \
  "${_RBAC}/replace-htpssd-test-user.sh" "${_E2E}"; do
  if [[ ! -f "${_p}" ]]; then
    echo "Missing expected file: ${_p}" >&2
    exit 1
  fi
done

echo "=== 1. z_coo.sh ==="
bash "${_UI}/z_coo.sh"

echo "=== 2. z_logging.sh ==="
bash "${_UI}/z_logging.sh"

echo "=== 3. z_tracing.sh ==="
bash "${_UI}/z_tracing.sh"

echo "=== 4. replace-htpssd-test-user.sh (non-interactive: not ROSA, namespace openshift-monitoring) ==="
cd "${_RBAC}"
printf 'n\nopenshift-monitoring\n' | bash ./replace-htpssd-test-user.sh

echo "=== 5. rbac_perses_e2e_user1_to_user6.sh ==="
bash "${_E2E}"

echo "=== 6. tempo_loki_thanos_persesglobaldatasource.sh ==="
bash "${_DEMO_DIR}/z_tempo_loki_thanos_persesglobaldatasource.sh"

echo "=== 7. dashboards.sh ==="
bash "${_DEMO_DIR}/../dashboards/dashboards.sh"

echo "Done (master.sh)."
