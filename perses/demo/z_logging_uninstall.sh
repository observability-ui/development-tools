#!/bin/bash
# Remove logging / Loki / MinIO / chat resources created by z_logging.sh so you can re-run a clean install.
#
# Order: Logging UIPlugin CR → ClusterLogForwarder → LokiStack → custom ClusterRoleBindings →
#        cluster-logging OLM → openshift-logging namespace →
#        Loki operator OLM (Subscription, InstallPlans, CSV) → optional redhat-operators ns →
#        minio + chat namespaces.
#
# Does NOT remove (by design):
#   - Cluster Observability Operator (deployment/CSV in openshift-cluster-observability-operator)
#   - OpenTelemetry or Tempo operators / openshift-tracing — use z_tracing_uninstall.sh
#   - Other UIPlugins (e.g. distributed-tracing); only the "logging" UIPlugin CR is deleted
#
# UIPlugin is cluster-scoped: use `oc delete uiplugin logging` (no -n namespace).
#
# Uses subscriptions.operators.coreos.com (not oc delete subscription — that can hit ACM API).
#
# Optional: KUBECONFIG_PATH, LOKI_NS (default openshift-operators-redhat),
#           DELETE_OPENSHIFT_OPERATORS_REDHAT_NS (default false)

set -euo pipefail

if [[ -n "${KUBECONFIG_PATH:-}" ]]; then
  OC_KC=(oc --kubeconfig "${KUBECONFIG_PATH}")
else
  OC_KC=(oc)
fi

LOKI_NS="${LOKI_NS:-openshift-operators-redhat}"
DELETE_OPENSHIFT_OPERATORS_REDHAT_NS="${DELETE_OPENSHIFT_OPERATORS_REDHAT_NS:-false}"

echo "=== 1. Logging UIPlugin CR only (does not uninstall Cluster Observability Operator) ==="
if "${OC_KC[@]}" get uiplugin logging &>/dev/null; then
  "${OC_KC[@]}" delete uiplugin logging --wait=true --timeout=120s
else
  echo "  (no cluster UIPlugin logging)"
fi

echo "=== 2. ClusterLogForwarder ==="
"${OC_KC[@]}" delete clusterlogforwarder.observability.openshift.io collector -n openshift-logging \
  --ignore-not-found --wait=true --timeout=300s || true

echo "=== 3. LokiStack (Loki operator workload in openshift-logging) ==="
"${OC_KC[@]}" delete lokistack logging-loki -n openshift-logging \
  --ignore-not-found --wait=true --timeout=600s || true

echo "=== 4. Custom ClusterRoleBindings (z-logging-*) ==="
"${OC_KC[@]}" delete clusterrolebinding \
  z-logging-logcollector-collect-application-logs \
  z-logging-logcollector-collect-infrastructure-logs \
  z-logging-logcollector-logging-collector-logs-writer \
  z-logging-logcollector-lokistack-tenant-logs \
  z-logging-collector-logging-collector-logs-writer \
  z-logging-collector-collect-application-logs \
  z-logging-collector-collect-infrastructure-logs \
  z-logging-collector-collect-audit-logs \
  --ignore-not-found

echo "=== 5. Cluster Logging operator (Subscription + CSVs in openshift-logging) ==="
"${OC_KC[@]}" delete subscriptions.operators.coreos.com cluster-logging -n openshift-logging \
  --ignore-not-found --wait=true --timeout=180s || true
while IFS= read -r csv; do
  [[ -z "$csv" ]] && continue
  "${OC_KC[@]}" delete "$csv" -n openshift-logging --ignore-not-found --wait=true --timeout=180s || true
done < <("${OC_KC[@]}" get csv -n openshift-logging -o name 2>/dev/null || true)

echo "=== 6. Namespace openshift-logging ==="
if "${OC_KC[@]}" get namespace openshift-logging &>/dev/null; then
  "${OC_KC[@]}" delete namespace openshift-logging --wait=true --timeout=600s || {
    echo "Namespace openshift-logging stuck terminating; you may need to clear finalizers on remaining resources." >&2
  }
fi

echo "=== 7. Loki operator (OLM in ${LOKI_NS}: Subscription → CSV → InstallPlans) ==="
"${OC_KC[@]}" delete subscriptions.operators.coreos.com loki-operator -n "$LOKI_NS" \
  --ignore-not-found --wait=true --timeout=180s || true

# Remove Loki CSVs (e.g. clusterserviceversions/.../loki-operator.v*)
while IFS= read -r csv; do
  [[ -z "$csv" ]] && continue
  if [[ "$csv" == *loki-operator* ]]; then
    "${OC_KC[@]}" delete "$csv" -n "$LOKI_NS" --ignore-not-found --wait=true --timeout=180s || true
  fi
done < <("${OC_KC[@]}" get csv -n "$LOKI_NS" -o name 2>/dev/null || true)

# InstallPlans labeled for this operator (after Sub/CSV removal)
"${OC_KC[@]}" delete installplan -n "$LOKI_NS" \
  -l operators.coreos.com/loki-operator.openshift-operators-redhat= \
  --ignore-not-found 2>/dev/null || true

if [[ "$DELETE_OPENSHIFT_OPERATORS_REDHAT_NS" == "true" ]]; then
  echo "=== 8. Delete namespace ${LOKI_NS} (DELETE_OPENSHIFT_OPERATORS_REDHAT_NS=true) ==="
  "${OC_KC[@]}" delete namespace "$LOKI_NS" --ignore-not-found --wait=true --timeout=300s || true
else
  echo "=== 8. Skipping namespace ${LOKI_NS} (Loki Subscription/CSV removed above; COO / Tempo / OpenTelemetry CSVs often remain here — not deleted by this script) ==="
  echo "    To delete the whole namespace: DELETE_OPENSHIFT_OPERATORS_REDHAT_NS=true. For tracing operators: z_tracing_uninstall.sh."
fi

echo "=== 9. MinIO and chat namespaces ==="
"${OC_KC[@]}" delete namespace minio chat --ignore-not-found --wait=true --timeout=300s || true

echo "Done (z_logging_uninstall.sh)."
echo "Not removed: Cluster Observability Operator; OpenTelemetry/Tempo/tracing stack — use z_tracing_uninstall.sh if you want those gone."
echo "You can re-run z_logging.sh when the cluster is ready."
