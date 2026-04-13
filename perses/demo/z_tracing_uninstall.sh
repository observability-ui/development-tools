#!/bin/bash
# Remove resources created by z_tracing.sh (embedded manifests: operators, openshift-tracing, sample apps).
# Order: UIPlugin distributed-tracing → sample app Projects → OpenTelemetryCollectors + TempoStack → ClusterRoleBindings/Roles →
#        openshift-tracing → user workload monitoring toggle → OLM (Subscription → CSV → InstallPlans) →
#        optional OperatorGroups → optional operator Projects.
#
# z_tracing.sh now resolves arbitrary CSV names via Subscription; uninstall must not rely on only
# *opentelemetry-product* / *tempo-product* name patterns. Default: purge all CSV + InstallPlan in
# each operator namespace (safe when each Project is dedicated to a single operator).
#
# Uses subscriptions.operators.coreos.com (not oc delete subscription — ACM API conflict).
#
# Env:
#   KUBECONFIG_PATH
#   COO_NS (UI plugin workloads; default openshift-cluster-observability-operator)
#   NS_TRACING, NS_TEMPO_OP, NS_OTEL_OP (same defaults as z_tracing.sh)
#   DELETE_TRACING_OPERATOR_NAMESPACES (default false)
#   REVERT_USER_WORKLOAD_MONITORING (default true)
#   PURGE_ALL_OLM_IN_OPERATOR_NS (default true — delete all CSV/InstallPlan in ${NS_OTEL_OP} and ${NS_TEMPO_OP})
#   DELETE_OPERATOR_GROUPS (default false — delete OperatorGroup in each operator namespace when not deleting Project)

set -euo pipefail

if [[ -n "${KUBECONFIG_PATH:-}" ]]; then
  OC_KC=(oc --kubeconfig "${KUBECONFIG_PATH}")
else
  OC_KC=(oc)
fi

NS_TRACING="${NS_TRACING:-openshift-tracing}"
NS_TEMPO_OP="${NS_TEMPO_OP:-openshift-tempo-operator}"
NS_OTEL_OP="${NS_OTEL_OP:-openshift-opentelemetry-operator}"
COO_NS="${COO_NS:-openshift-cluster-observability-operator}"
DELETE_TRACING_OPERATOR_NAMESPACES="${DELETE_TRACING_OPERATOR_NAMESPACES:-false}"
REVERT_USER_WORKLOAD_MONITORING="${REVERT_USER_WORKLOAD_MONITORING:-true}"
PURGE_ALL_OLM_IN_OPERATOR_NS="${PURGE_ALL_OLM_IN_OPERATOR_NS:-true}"
DELETE_OPERATOR_GROUPS="${DELETE_OPERATOR_GROUPS:-false}"

# Remove OLM objects for one operator package in a namespace.
purge_operator_olm() {
  local ns=$1
  local sub_name=$2
  local ip_label_key=$3

  [[ -z "$ns" ]] && return 0
  if ! "${OC_KC[@]}" get namespace "$ns" &>/dev/null; then
    return 0
  fi

  echo "  Purge OLM in ${ns} (Subscription ${sub_name})"
  "${OC_KC[@]}" delete subscriptions.operators.coreos.com "$sub_name" -n "$ns" \
    --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true

  if [[ "${PURGE_ALL_OLM_IN_OPERATOR_NS}" == "true" ]]; then
    "${OC_KC[@]}" delete csv --all -n "$ns" --ignore-not-found --wait=true --timeout=300s 2>/dev/null || true
    "${OC_KC[@]}" delete installplan --all -n "$ns" --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true
  else
    while IFS= read -r csv; do
      [[ -z "$csv" ]] && continue
      local base=${csv##*/}
      local match=0
      if [[ "$sub_name" == "opentelemetry-product" ]] && [[ "$base" == *opentelemetry* ]]; then match=1; fi
      if [[ "$sub_name" == "tempo-product" ]] && [[ "$base" == *tempo* ]]; then match=1; fi
      if [[ "$match" -eq 1 ]]; then
        "${OC_KC[@]}" delete "$csv" -n "$ns" --ignore-not-found --wait=true --timeout=180s || true
      fi
    done < <("${OC_KC[@]}" get csv -n "$ns" -o name 2>/dev/null || true)
    "${OC_KC[@]}" delete installplan -n "$ns" -l "${ip_label_key}" --ignore-not-found 2>/dev/null || true
  fi

  if [[ -n "${ip_label_key}" ]]; then
    "${OC_KC[@]}" delete installplan -n "$ns" -l "${ip_label_key}" --ignore-not-found 2>/dev/null || true
  fi
}

echo "=== 1. Distributed Tracing UIPlugin (Observe → Tracing) ==="
if "${OC_KC[@]}" get uiplugin distributed-tracing &>/dev/null; then
  "${OC_KC[@]}" delete uiplugin distributed-tracing --wait=true --timeout=120s
else
  echo "  (no cluster UIPlugin distributed-tracing)"
fi

echo "=== 2. Sample tracing apps (Projects: tracing-app-*) ==="
for ns in tracing-app-hotrod tracing-app-k6 tracing-app-telemetrygen; do
  if "${OC_KC[@]}" get project "$ns" &>/dev/null || "${OC_KC[@]}" get namespace "$ns" &>/dev/null; then
    "${OC_KC[@]}" delete project "$ns" --ignore-not-found --wait=true --timeout=300s 2>/dev/null \
      || "${OC_KC[@]}" delete namespace "$ns" --ignore-not-found --wait=true --timeout=300s 2>/dev/null || true
  fi
done

echo "=== 3. OpenTelemetryCollectors + TempoStack (${NS_TRACING}) ==="
if "${OC_KC[@]}" get namespace "$NS_TRACING" &>/dev/null; then
  "${OC_KC[@]}" delete opentelemetrycollector platform user -n "$NS_TRACING" \
    --ignore-not-found --wait=true --timeout=300s 2>/dev/null || true
  "${OC_KC[@]}" delete opentelemetrycollectors.opentelemetry.io platform user -n "$NS_TRACING" \
    --ignore-not-found --wait=true --timeout=300s 2>/dev/null || true
  "${OC_KC[@]}" delete tempostack platform -n "$NS_TRACING" \
    --ignore-not-found --wait=true --timeout=600s 2>/dev/null || true
  "${OC_KC[@]}" delete tempostacks.tempo.grafana.com platform -n "$NS_TRACING" \
    --ignore-not-found --wait=true --timeout=600s 2>/dev/null || true
fi

echo "=== 4. ClusterRoleBindings + ClusterRoles (from tempo.yaml + otel collectors) ==="
"${OC_KC[@]}" delete clusterrolebinding \
  traces-writer-user \
  traces-writer-platform \
  openshift-tracing-user-collector \
  openshift-tracing-platform-collector \
  traces-reader-platform \
  traces-reader-user \
  --ignore-not-found

"${OC_KC[@]}" delete clusterrole \
  traces-writer-user \
  traces-writer-platform \
  openshift-tracing-user-collector \
  openshift-tracing-platform-collector \
  traces-reader-platform \
  traces-reader-user \
  --ignore-not-found

echo "=== 5. Namespace/Project ${NS_TRACING} ==="
if "${OC_KC[@]}" get namespace "$NS_TRACING" &>/dev/null; then
  "${OC_KC[@]}" delete namespace "$NS_TRACING" --ignore-not-found --wait=true --timeout=600s || {
    echo "Warning: ${NS_TRACING} stuck terminating; check finalizers." >&2
  }
fi

if [[ "${REVERT_USER_WORKLOAD_MONITORING}" == "true" ]]; then
  echo "=== 6. User workload monitoring (revert enableUserWorkload) ==="
  if "${OC_KC[@]}" get configmap cluster-monitoring-config -n openshift-monitoring &>/dev/null; then
    "${OC_KC[@]}" patch configmap cluster-monitoring-config -n openshift-monitoring --type merge -p $'{"data":{"config.yaml":"enableUserWorkload: false\\n"}}' 2>/dev/null \
      || echo "Warning: could not patch cluster-monitoring-config (merge with existing keys may be needed)." >&2
  fi
else
  echo "=== 6. Skipping cluster-monitoring-config (REVERT_USER_WORKLOAD_MONITORING=false) ==="
fi

echo "=== 7. OpenTelemetry operator OLM (${NS_OTEL_OP}) ==="
purge_operator_olm "$NS_OTEL_OP" opentelemetry-product 'operators.coreos.com/opentelemetry-product.openshift-opentelemetry-operator='

echo "=== 8. Tempo operator OLM (${NS_TEMPO_OP}) ==="
purge_operator_olm "$NS_TEMPO_OP" tempo-product 'operators.coreos.com/tempo-product.openshift-tempo-operator='

if [[ "${DELETE_OPERATOR_GROUPS}" == "true" ]]; then
  echo "=== 8b. OperatorGroups (DELETE_OPERATOR_GROUPS=true) ==="
  "${OC_KC[@]}" delete operatorgroup openshift-opentelemetry-operator -n "$NS_OTEL_OP" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
  "${OC_KC[@]}" delete operatorgroup openshift-tempo-operator -n "$NS_TEMPO_OP" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
fi

if [[ "$DELETE_TRACING_OPERATOR_NAMESPACES" == "true" ]]; then
  echo "=== 9. Delete operator Projects (${NS_OTEL_OP}, ${NS_TEMPO_OP}) ==="
  "${OC_KC[@]}" delete project "$NS_OTEL_OP" --ignore-not-found --wait=true --timeout=300s 2>/dev/null \
    || "${OC_KC[@]}" delete namespace "$NS_OTEL_OP" --ignore-not-found --wait=true --timeout=300s || true
  "${OC_KC[@]}" delete project "$NS_TEMPO_OP" --ignore-not-found --wait=true --timeout=300s 2>/dev/null \
    || "${OC_KC[@]}" delete namespace "$NS_TEMPO_OP" --ignore-not-found --wait=true --timeout=300s || true
else
  echo "=== 9. Skipping operator Projects (set DELETE_TRACING_OPERATOR_NAMESPACES=true to remove ${NS_OTEL_OP} and ${NS_TEMPO_OP}) ==="
fi

echo "Done (z_tracing_uninstall.sh)."
