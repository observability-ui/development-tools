#!/bin/bash
# Remove Cluster Observability Operator operands: PersesGlobalDatasource (z_coo.sh), UIPlugins,
# ObservabilityInstallers, then Subscription/CSV/InstallPlans in the COO namespace (OperatorHub install).
# Does not remove redhat-operators CatalogSource or unrelated namespaces.
#
# Env:
#   KUBECONFIG_PATH
#   COO_NS (default openshift-cluster-observability-operator)
#   COO_SUBSCRIPTION (default cluster-observability-operator; must match z_coo.sh)
#   DELETE_PERSES_GLOBAL_DATASOURCES (default true — Thanos/Loki/Tempo PersesGlobalDatasource from z_coo.sh)
#   DELETE_COO_UIPLUGINS (default true — delete all cluster UIPlugin CRs, including monitoring from z_coo.sh)
#   DELETE_COO_OBSERVABILITY_INSTALLERS (default true — delete all ObservabilityInstaller CRs in every namespace)
#   PURGE_ALL_CSV_IN_COO_NS (default true — delete all CSV/InstallPlan in COO_NS after Subscription delete)
#   DELETE_COO_NAMESPACE (default false — delete Project/Namespace COO_NS when true)
#
# Note: Other Perses CRs (dashboards, etc.) and MonitoringStack are not bulk-deleted here.
#
# Uses subscriptions.operators.coreos.com

set -euo pipefail

if [[ -n "${KUBECONFIG_PATH:-}" ]]; then
  OC_KC=(oc --kubeconfig "${KUBECONFIG_PATH}")
else
  OC_KC=(oc)
fi

COO_NS="${COO_NS:-openshift-cluster-observability-operator}"
COO_SUBSCRIPTION="${COO_SUBSCRIPTION:-cluster-observability-operator}"
DELETE_PERSES_GLOBAL_DATASOURCES="${DELETE_PERSES_GLOBAL_DATASOURCES:-true}"
DELETE_COO_UIPLUGINS="${DELETE_COO_UIPLUGINS:-true}"
DELETE_COO_OBSERVABILITY_INSTALLERS="${DELETE_COO_OBSERVABILITY_INSTALLERS:-true}"
PURGE_ALL_CSV_IN_COO_NS="${PURGE_ALL_CSV_IN_COO_NS:-true}"
DELETE_COO_NAMESPACE="${DELETE_COO_NAMESPACE:-false}"

delete_perses_global_datasources_z_coo() {
  if ! "${OC_KC[@]}" get crd persesglobaldatasources.perses.dev &>/dev/null; then
    echo "  (CRD persesglobaldatasources.perses.dev not found; skipping)"
    return 0
  fi
  local n
  for n in thanos-querier-datasource loki-datasource tempo-platform; do
    if "${OC_KC[@]}" get persesglobaldatasources.perses.dev "$n" &>/dev/null; then
      echo "  delete PersesGlobalDatasource/${n}"
      "${OC_KC[@]}" delete persesglobaldatasources.perses.dev "$n" --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true
    fi
  done
}

delete_coo_uiplugins() {
  if ! "${OC_KC[@]}" get crd uiplugins.observability.openshift.io &>/dev/null; then
    echo "  (CRD uiplugins.observability.openshift.io not found; skipping UIPlugins)"
    return 0
  fi
  local any=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    any=1
    echo "  delete $line"
    "${OC_KC[@]}" delete "$line" --wait=true --timeout=180s 2>/dev/null || true
  done < <("${OC_KC[@]}" get uiplugins.observability.openshift.io -o name 2>/dev/null || true)
  if [[ "$any" -eq 0 ]]; then
    echo "  (no UIPlugin resources)"
  fi
}

delete_coo_observability_installers() {
  if ! "${OC_KC[@]}" get crd observabilityinstallers.observability.openshift.io &>/dev/null; then
    echo "  (CRD observabilityinstallers.observability.openshift.io not found; skipping ObservabilityInstallers)"
    return 0
  fi
  if ! "${OC_KC[@]}" get observabilityinstallers.observability.openshift.io --all-namespaces -o name 2>/dev/null | grep -q .; then
    echo "  delete ObservabilityInstaller instances (--all-namespaces --all)"
    "${OC_KC[@]}" delete observabilityinstallers.observability.openshift.io --all-namespaces --all \
      --wait=true --timeout=600s 2>/dev/null || true
  else
    echo "  (no ObservabilityInstaller resources)"
  fi
}

purge_coo_olm() {
  echo "  Delete Subscription ${COO_SUBSCRIPTION} in ${COO_NS}"
  "${OC_KC[@]}" delete subscriptions.operators.coreos.com "$COO_SUBSCRIPTION" -n "$COO_NS" \
    --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true

  if [[ "${PURGE_ALL_CSV_IN_COO_NS}" == "true" ]]; then
    "${OC_KC[@]}" delete csv --all -n "$COO_NS" --ignore-not-found --wait=true --timeout=300s 2>/dev/null || true
    "${OC_KC[@]}" delete installplan --all -n "$COO_NS" --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true
  fi
}

echo "=== 1. PersesGlobalDatasource (Thanos / Loki / Tempo — z_coo.sh) ==="
if [[ "${DELETE_PERSES_GLOBAL_DATASOURCES}" == "true" ]]; then
  delete_perses_global_datasources_z_coo
else
  echo "  Skipped (DELETE_PERSES_GLOBAL_DATASOURCES=false)"
fi

echo "=== 2. COO operands: UIPlugins (cluster, includes monitoring) ==="
if [[ "${DELETE_COO_UIPLUGINS}" == "true" ]]; then
  delete_coo_uiplugins
else
  echo "  Skipped (DELETE_COO_UIPLUGINS=false)"
fi

echo "=== 3. COO operands: ObservabilityInstallers (all namespaces) ==="
if [[ "${DELETE_COO_OBSERVABILITY_INSTALLERS}" == "true" ]]; then
  delete_coo_observability_installers
else
  echo "  Skipped (DELETE_COO_OBSERVABILITY_INSTALLERS=false)"
fi

echo "=== 4. Cluster Observability Operator OLM (${COO_NS}) ==="
if ! "${OC_KC[@]}" get namespace "$COO_NS" &>/dev/null && ! "${OC_KC[@]}" get project "$COO_NS" &>/dev/null; then
  echo "  Namespace ${COO_NS} not found; skipping OLM purge."
else
  purge_coo_olm
fi

if [[ "${DELETE_COO_NAMESPACE}" == "true" ]]; then
  echo "=== 5. Delete namespace ${COO_NS} (DELETE_COO_NAMESPACE=true) ==="
  "${OC_KC[@]}" delete project "$COO_NS" --ignore-not-found --wait=true --timeout=600s 2>/dev/null \
    || "${OC_KC[@]}" delete namespace "$COO_NS" --ignore-not-found --wait=true --timeout=600s 2>/dev/null || true
else
  echo "=== 5. Skipping namespace ${COO_NS} (set DELETE_COO_NAMESPACE=true to remove) ==="
fi

echo "Done (z_coo_uninstall.sh)."
