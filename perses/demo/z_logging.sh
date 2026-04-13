#!/bin/bash
# Single script: MinIO, chat workload, Cluster Logging + Loki operators, LokiStack,
# RBAC, ClusterLogForwarder, Logging UIPlugin. All YAML is embedded below.
#
# Env (optional):
#   KUBECONFIG_PATH
#   COO_NS — namespace for UI plugin Deployments (default openshift-cluster-observability-operator)
#   LOKI_NS (default openshift-operators-redhat)
#   STORAGE_CLASS_NAME (default gp3-csi) or STORAGE_CLASS_AUTO=true for cluster default SC
#   CLUSTER_LOGGING_CHANNEL — default "auto" = PackageManifest defaultChannel
#   LOKI_OPERATOR_CHANNEL — default "auto" = greatest stable-* from PackageManifest channels (version sort, e.g. stable-6.5 over stable-6.1; ignores alpha/defaultChannel)
#     (Shell export LOKI_OPERATOR_CHANNEL=alpha is ignored unless LOKI_ALLOW_ALPHA_CHANNEL=true.)
#   OLM_POLL_INTERVAL — seconds between CSV checks (default 5)
#   OPERATOR_INSTALL_TIMEOUT — wait for OLM CSV Succeeded (default 900s)
#   ROLLOUT_TIMEOUT — deployment rollouts (default 600s)
#
# Use: oc get subscriptions.operators.coreos.com (not oc get subscription — that can hit ACM API)

set -euo pipefail

if [[ -n "${KUBECONFIG_PATH:-}" ]]; then
  OC_KC=(oc --kubeconfig "${KUBECONFIG_PATH}")
else
  OC_KC=(oc)
fi

LOKI_NS="${LOKI_NS:-openshift-operators-redhat}"
CLUSTER_LOGGING_CHANNEL="${CLUSTER_LOGGING_CHANNEL:-auto}"
LOKI_OPERATOR_CHANNEL="${LOKI_OPERATOR_CHANNEL:-auto}"
# Exporting LOKI_OPERATOR_CHANNEL=alpha overrides :-auto and skips OperatorHub resolution; remap unless you really want alpha.
if [[ "${LOKI_OPERATOR_CHANNEL}" == "alpha" ]] && [[ "${LOKI_ALLOW_ALPHA_CHANNEL:-}" != "true" ]]; then
  echo "Note: LOKI_OPERATOR_CHANNEL=alpha is ignored; using greatest stable-* from PackageManifest channels. Set LOKI_ALLOW_ALPHA_CHANNEL=true to subscribe to alpha." >&2
  LOKI_OPERATOR_CHANNEL=auto
fi
OLM_POLL_INTERVAL="${OLM_POLL_INTERVAL:-5}"
OPERATOR_INSTALL_TIMEOUT="${OPERATOR_INSTALL_TIMEOUT:-900}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-600}"
COO_NS="${COO_NS:-openshift-cluster-observability-operator}"

# Use catalog defaultChannel so OLM resolves quickly (wrong channel = slow or no CSV).
resolve_channel_from_catalog() {
  local pkg=$1
  local fallback=${2:-stable}
  local ch
  ch=$("${OC_KC[@]}" get packagemanifest "$pkg" -n openshift-marketplace -o jsonpath='{.status.defaultChannel}' 2>/dev/null || true)
  if [[ -n "$ch" ]]; then
    echo "$ch"
  else
    echo "$fallback"
  fi
}

# Pick greatest stable-* from PackageManifest (version sort). Merges channel list + defaultChannel
# (some oc/jsonpath forms omit names; defaultChannel is often stable-6.x even when bare "stable" appears in lists).
resolve_loki_channel_from_packagemanifest_channels() {
  local lines json def combined best fb
  lines=$("${OC_KC[@]}" get packagemanifest loki-operator -n openshift-marketplace \
    -o jsonpath='{range .status.channels[*]}{.name}{"\n"}{end}' 2>/dev/null || true)
  lines=${lines//$'\r'/}
  if [[ -z "${lines// }" ]] && command -v jq &>/dev/null; then
    json=$("${OC_KC[@]}" get packagemanifest loki-operator -n openshift-marketplace -o json 2>/dev/null || true)
    [[ -n "${json// }" ]] && lines=$(echo "$json" | jq -r '(.status.channels // [])[] | .name? // empty' 2>/dev/null || true)
  fi
  def=$("${OC_KC[@]}" get packagemanifest loki-operator -n openshift-marketplace -o jsonpath='{.status.defaultChannel}' 2>/dev/null || true)
  def=${def//$'\r'/}
  # Candidates: every channel row + defaultChannel (echo preserves newlines in $lines).
  combined=$( (echo "$lines"; echo "$def") | sed '/^[[:space:]]*$/d' || true )

  [[ -z "${combined// }" ]] && {
    fb=$(resolve_channel_from_catalog loki-operator)
    [[ "$fb" == "alpha" || -z "${fb// }" ]] && fb="stable"
    echo "$fb"
    return
  }

  # Numeric stable-X(.Y)* …
  best=$(echo "$combined" | grep -E '^stable-[0-9]+([.][0-9]+)*$' | sort -uV | tail -1 || true)
  if [[ -n "$best" ]]; then
    echo "$best"
    return
  fi
  # Any stable-* (not bare "stable")
  best=$(echo "$combined" | grep -E '^stable-.+' | sort -uV | tail -1 || true)
  if [[ -n "$best" ]]; then
    echo "$best"
    return
  fi
  if echo "$combined" | grep -qx 'stable'; then
    echo 'stable'
    return
  fi
  fb=$(resolve_channel_from_catalog loki-operator)
  [[ "$fb" == "alpha" || -z "${fb// }" ]] && fb="stable"
  echo "$fb"
}

resolve_loki_operator_channel_auto() {
  resolve_loki_channel_from_packagemanifest_channels
}

if [[ "${CLUSTER_LOGGING_CHANNEL}" == "auto" ]]; then
  CLUSTER_LOGGING_CHANNEL=$(resolve_channel_from_catalog cluster-logging)
  echo "cluster-logging Subscription channel: ${CLUSTER_LOGGING_CHANNEL} (PackageManifest defaultChannel)"
fi
if [[ "${LOKI_OPERATOR_CHANNEL}" == "auto" ]]; then
  LOKI_OPERATOR_CHANNEL=$(resolve_loki_operator_channel_auto)
  echo "loki-operator Subscription channel: ${LOKI_OPERATOR_CHANNEL} (greatest stable-* from catalog)"
fi

# If Subscription lists status.installedCSV but that CSV object is gone, OLM is stuck — delete Sub + InstallPlans so apply can recreate.
repair_orphaned_subscription() {
  local ns=$1
  local sub_name=$2
  local installplan_label_key=$3
  if ! "${OC_KC[@]}" get subscriptions.operators.coreos.com "$sub_name" -n "$ns" &>/dev/null; then
    return 0
  fi
  local installed
  installed=$("${OC_KC[@]}" get subscriptions.operators.coreos.com "$sub_name" -n "$ns" -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)
  [[ -z "$installed" ]] && return 0
  if "${OC_KC[@]}" get csv "$installed" -n "$ns" &>/dev/null; then
    return 0
  fi
  echo "OLM repair: ${sub_name} (${ns}) references missing CSV ${installed}; deleting Subscription and InstallPlans"
  "${OC_KC[@]}" delete subscriptions.operators.coreos.com "$sub_name" -n "$ns" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
  if [[ -n "${installplan_label_key}" ]]; then
    "${OC_KC[@]}" delete installplan -n "$ns" -l "${installplan_label_key}" --ignore-not-found 2>/dev/null || true
  fi
  sleep 3
}

# StorageClass: default gp3-csi (AWS); set STORAGE_CLASS_AUTO=true to use the cluster default StorageClass.
if [[ "${STORAGE_CLASS_AUTO:-false}" == "true" ]]; then
  STORAGE_CLASS_NAME=$("${OC_KC[@]}" get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || true)
  if [[ -z "$STORAGE_CLASS_NAME" ]]; then
    STORAGE_CLASS_NAME=$("${OC_KC[@]}" get storageclass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  fi
  if [[ -z "$STORAGE_CLASS_NAME" ]]; then
    echo "STORAGE_CLASS_AUTO=true but no StorageClass found; set STORAGE_CLASS_NAME explicitly." >&2
    exit 1
  fi
  echo "Using StorageClass: ${STORAGE_CLASS_NAME} (STORAGE_CLASS_AUTO)"
else
  STORAGE_CLASS_NAME="${STORAGE_CLASS_NAME:-gp3-csi}"
fi

wait_until() {
  local msg=$1
  local timeout_sec=$2
  shift 2
  local deadline=$(( $(date +%s) + timeout_sec ))
  echo "Waiting (up to ${timeout_sec}s): $msg"
  while (( $(date +%s) < deadline )); do
    if "$@"; then
      return 0
    fi
    sleep 10
  done
  echo "Timeout: $msg" >&2
  return 1
}

collector_pods_running() {
  local n
  n=$("${OC_KC[@]}" get pods -n openshift-logging -l component=collector --no-headers 2>/dev/null | awk '$3=="Running" {c++} END {print c+0}')
  [[ "${n:-0}" -ge 1 ]]
}

# Wait until OLM has installed a CSV whose name starts with prefix (e.g. loki-operator, cluster-logging).
wait_csv_succeeded() {
  local ns=$1
  local prefix=$2
  local deadline=$(( $(date +%s) + OPERATOR_INSTALL_TIMEOUT ))
  echo "Waiting for CSV ${prefix}* phase=Succeeded in ${ns} (up to ${OPERATOR_INSTALL_TIMEOUT}s)"
  while (( $(date +%s) < deadline )); do
    while IFS=$'\t' read -r cname phase; do
      [[ -z "$cname" ]] && continue
      if [[ "$cname" == ${prefix}* ]] && [[ "$phase" == "Succeeded" ]]; then
        echo "CSV ready: ${cname}"
        return 0
      fi
    done < <("${OC_KC[@]}" get csv -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}' 2>/dev/null || true)
    sleep "${OLM_POLL_INTERVAL}"
  done
  echo "Timeout: no Succeeded CSV matching ${prefix}* in ${ns}" >&2
  "${OC_KC[@]}" get subscriptions.operators.coreos.com -n "$ns" -o wide 2>/dev/null || true
  "${OC_KC[@]}" get csv -n "$ns" -o wide 2>/dev/null || true
  "${OC_KC[@]}" get installplan -n "$ns" -o wide 2>/dev/null || true
  return 1
}

# After CSV succeeds, wait for the Loki operator controller to be Ready (pod name varies by release).
wait_loki_operator_rollout() {
  echo "Waiting for Loki operator workload in ${LOKI_NS}"
  local deadline=$(( $(date +%s) + OPERATOR_INSTALL_TIMEOUT ))
  local dep
  while (( $(date +%s) < deadline )); do
    dep=$("${OC_KC[@]}" get deploy -n "$LOKI_NS" -o name 2>/dev/null | grep -i loki | head -1 || true)
    if [[ -n "$dep" ]]; then
      echo "Rollout: ${dep}"
      "${OC_KC[@]}" rollout status "$dep" -n "$LOKI_NS" --timeout="${ROLLOUT_TIMEOUT}s"
      return 0
    fi
    # Fallback: any pod with loki in the name
    if "${OC_KC[@]}" get pods -n "$LOKI_NS" -o name 2>/dev/null | grep -qi loki; then
      local pn
      pn=$("${OC_KC[@]}" get pods -n "$LOKI_NS" -o name 2>/dev/null | grep -i loki | head -1 | tr -d '\r')
      echo "Waiting for pod Ready: ${pn}"
      "${OC_KC[@]}" wait --for=condition=Ready "$pn" -n "$LOKI_NS" --timeout="${ROLLOUT_TIMEOUT}s"
      return 0
    fi
    sleep 10
  done
  echo "Timeout: Loki operator deployment/pod not found in ${LOKI_NS}" >&2
  "${OC_KC[@]}" get deploy,pods -n "$LOKI_NS" 2>/dev/null || true
  return 1
}

# --- 1. MinIO ---
echo "Apply MinIO"
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: minio
---
apiVersion: v1
kind: Secret
metadata:
  name: minio
  namespace: minio
stringData:
  access_key_id: minio
  access_key_secret: minio123
  bucketnames: loki
  endpoint: http://minio.minio.svc:9000
type: Opaque
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: minio
spec:
  ports:
  - port: 9000
    protocol: TCP
    targetPort: 9000
  selector:
    app.kubernetes.io/name: minio
  type: ClusterIP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/name: minio
  name: minio
  namespace: minio
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: minio
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app.kubernetes.io/name: minio
    spec:
      containers:
      - command:
        - /bin/sh
        - -c
        - |
          mkdir -p /storage/loki && \
          minio server /storage
        env:
        - name: MINIO_ACCESS_KEY
          value: minio
        - name: MINIO_SECRET_KEY
          value: minio123
        image: quay.io/minio/minio
        name: minio
        ports:
        - containerPort: 9000
        volumeMounts:
        - mountPath: /storage
          name: storage
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: minio
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    app.kubernetes.io/name: minio
  name: minio
  namespace: minio
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

echo "Wait for MinIO rollout"
"${OC_KC[@]}" rollout status deployment/minio -n minio --timeout="${ROLLOUT_TIMEOUT}s"

# --- 2. Chat log generator ---
echo "Apply chat workload"
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: chat
---
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: chat
    test: "true"
  name: chat-x
  namespace: chat
spec:
  containers:
  - name: chat
    image: quay.io/libpod/alpine
    command:
    - sh
    - "-c"
    - 'i=1; while true; do echo "$(date) chat says hello - $i"; i=$((i + 1)); sleep 1; done'
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      seccompProfile:
        type: "RuntimeDefault"
      capabilities:
        drop: [ALL]
EOF
"${OC_KC[@]}" wait pod/chat-x -n chat --for=condition=Ready --timeout=180s \
  || echo "Warning: chat pod not Ready yet (continuing; optional workload)."

# --- 3. Operators: Cluster Logging + Loki subscriptions ---
repair_orphaned_subscription openshift-logging cluster-logging 'operators.coreos.com/cluster-logging.openshift-logging='

echo "Apply Cluster Logging operator (namespace, OperatorGroup, Subscription channel=${CLUSTER_LOGGING_CHANNEL})"
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-logging
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  namespace: openshift-logging
  name: openshift-logging
  labels:
    og_label: openshift-logging
spec:
  targetNamespaces:
  - openshift-logging
  upgradeStrategy: Default
EOF

cat <<EOF | "${OC_KC[@]}" apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-logging
  namespace: openshift-logging
spec:
  channel: ${CLUSTER_LOGGING_CHANNEL}
  installPlanApproval: Automatic
  name: cluster-logging
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

repair_orphaned_subscription "$LOKI_NS" loki-operator 'operators.coreos.com/loki-operator.openshift-operators-redhat='

echo "Apply Loki operator (namespace, OperatorGroup, Subscription channel=${LOKI_OPERATOR_CHANNEL})"
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-operators-redhat
  annotations:
    openshift.io/node-selector: ""
  labels:
    openshift.io/cluster-logging: "true"
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-operators-redhat
  namespace: openshift-operators-redhat
spec: {}
EOF

cat <<EOF | "${OC_KC[@]}" apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: loki-operator
  namespace: openshift-operators-redhat
spec:
  channel: ${LOKI_OPERATOR_CHANNEL}
  installPlanApproval: Automatic
  name: loki-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Ensure spec.channel matches (existing Subscription may have been on alpha; merge apply can leave old channel).
"${OC_KC[@]}" patch subscriptions.operators.coreos.com loki-operator -n "${LOKI_NS}" \
  --type=merge -p "$(printf '%s' "{\"spec\":{\"channel\":\"${LOKI_OPERATOR_CHANNEL}\"}}")" 2>/dev/null || true

# Both operators install independently — wait for both CSVs in parallel (saves time).
echo "Wait for Cluster Logging + Loki operator CSVs (parallel, poll every ${OLM_POLL_INTERVAL}s)"
wait_csv_succeeded openshift-logging cluster-logging &
_pid_cl_csv=$!
wait_csv_succeeded "$LOKI_NS" loki-operator &
_pid_loki_csv=$!
_csv_ec=0
wait $_pid_cl_csv || _csv_ec=1
wait $_pid_loki_csv || _csv_ec=1
if ((_csv_ec != 0)); then
  exit 1
fi

# Roll out both operator workloads in parallel.
echo "Wait for Cluster Logging + Loki operator Deployments (parallel)"
(
  wait_until "cluster-logging-operator deployment in openshift-logging" "${ROLLOUT_TIMEOUT}" \
    "${OC_KC[@]}" get deployment cluster-logging-operator -n openshift-logging -o name &>/dev/null
  "${OC_KC[@]}" wait deployment cluster-logging-operator -n openshift-logging \
    --for=condition=Available --timeout="${ROLLOUT_TIMEOUT}s"
) &
_pid_cl_rollout=$!
wait_loki_operator_rollout &
_pid_loki_rollout=$!
_roll_ec=0
wait $_pid_cl_rollout || _roll_ec=1
wait $_pid_loki_rollout || _roll_ec=1
if ((_roll_ec != 0)); then
  exit 1
fi

# --- 5. LokiStack + Secret (STORAGE_CLASS_NAME replaces REPLACE) ---
echo "Apply Secret + LokiStack (storage class: ${STORAGE_CLASS_NAME})"
sed "s|REPLACE|${STORAGE_CLASS_NAME}|g" <<'EOF' | "${OC_KC[@]}" apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: minio
  namespace: openshift-logging
stringData:
  access_key_id: minio
  access_key_secret: minio123
  bucketnames: loki
  endpoint: http://minio.minio.svc:9000
type: Opaque
---
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  size: 1x.demo
  storage:
    schemas:
    - version: v12
      effectiveDate: '2022-06-01'
    secret:
      name: minio
      type: s3
  storageClassName: REPLACE
  tenants:
    mode: openshift-logging
EOF

echo "Wait for Loki gateway deployment (LokiStack reconciled)"
wait_until "deployment logging-loki-gateway in openshift-logging" "${ROLLOUT_TIMEOUT}" \
  "${OC_KC[@]}" get deployment logging-loki-gateway -n openshift-logging -o name &>/dev/null
"${OC_KC[@]}" rollout status deployment/logging-loki-gateway -n openshift-logging --timeout="${ROLLOUT_TIMEOUT}s"

# --- 6. ServiceAccounts + ClusterRoleBindings ---
echo "Apply logcollector ServiceAccount + RBAC"
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: logcollector
  namespace: openshift-logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: z-logging-logcollector-collect-application-logs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: collect-application-logs
subjects:
- kind: ServiceAccount
  name: logcollector
  namespace: openshift-logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: z-logging-logcollector-collect-infrastructure-logs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: collect-infrastructure-logs
subjects:
- kind: ServiceAccount
  name: logcollector
  namespace: openshift-logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: z-logging-logcollector-logging-collector-logs-writer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: logging-collector-logs-writer
subjects:
- kind: ServiceAccount
  name: logcollector
  namespace: openshift-logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: z-logging-logcollector-lokistack-tenant-logs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: lokistack-tenant-logs
subjects:
- kind: ServiceAccount
  name: logcollector
  namespace: openshift-logging
EOF

echo "Apply collector ServiceAccount + RBAC (includes collect-infrastructure-logs for CLF)"
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: collector
  namespace: openshift-logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: z-logging-collector-logging-collector-logs-writer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: logging-collector-logs-writer
subjects:
- kind: ServiceAccount
  name: collector
  namespace: openshift-logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: z-logging-collector-collect-application-logs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: collect-application-logs
subjects:
- kind: ServiceAccount
  name: collector
  namespace: openshift-logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: z-logging-collector-collect-infrastructure-logs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: collect-infrastructure-logs
subjects:
- kind: ServiceAccount
  name: collector
  namespace: openshift-logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: z-logging-collector-collect-audit-logs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: collect-audit-logs
subjects:
- kind: ServiceAccount
  name: collector
  namespace: openshift-logging
EOF

# --- 7. ClusterLogForwarder (needs collector RBAC + Loki gateway) ---
echo "Apply ClusterLogForwarder"
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: collector
  namespace: openshift-logging
spec:
  serviceAccount:
    name: collector
  outputs:
    - name: default-lokistack
      type: lokiStack
      lokiStack:
        target:
          name: logging-loki
          namespace: openshift-logging
        authentication:
          token:
            from: serviceAccount
      tls:
        ca:
          key: service-ca.crt
          configMapName: openshift-service-ca.crt
  pipelines:
    - name: default-logstore
      inputRefs:
        - application
        - infrastructure
      outputRefs:
        - default-lokistack
EOF

echo "Wait for ClusterLogForwarder Ready"
if ! "${OC_KC[@]}" wait clusterlogforwarder.observability.openshift.io/collector -n openshift-logging \
  --for=condition=Ready --timeout="${ROLLOUT_TIMEOUT}s" 2>/dev/null; then
  echo "oc wait CLF Ready not supported or timed out; waiting for collector pods to exist and run"
  wait_until "collector pods in openshift-logging" "${ROLLOUT_TIMEOUT}" collector_pods_running
fi

# --- 8. Logging UI plugin ---
echo "Apply Logging UIPlugin"
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: logging
spec:
  type: Logging
  logging:
    lokiStack:
      name: logging-loki
    logsLimit: 50
    timeout: 30s
    schema: select
EOF

echo "Wait for Logging UIPlugin Available and console plugin workload in ${COO_NS}"
if "${OC_KC[@]}" wait uiplugin logging --for=condition=Available --timeout="${ROLLOUT_TIMEOUT}s" 2>/dev/null; then
  echo "UIPlugin logging: condition Available"
else
  echo "Note: oc wait UIPlugin Available skipped, failed, or timed out; checking Deployment/Pods in ${COO_NS}." >&2
fi

if wait_until "deployment logging in ${COO_NS}" "${ROLLOUT_TIMEOUT}" \
  "${OC_KC[@]}" get deployment logging -n "${COO_NS}" -o name &>/dev/null; then
  "${OC_KC[@]}" rollout status deployment/logging -n "${COO_NS}" --timeout="${ROLLOUT_TIMEOUT}s"
  if "${OC_KC[@]}" wait pod -n "${COO_NS}" \
    -l "app.kubernetes.io/instance=logging,app.kubernetes.io/part-of=UIPlugin" \
    --for=condition=Ready --timeout="${ROLLOUT_TIMEOUT}s" 2>/dev/null; then
    echo "Logging plugin pod(s) Ready (${COO_NS})"
  else
    echo "Warning: pod Ready wait failed; current pods:" >&2
    "${OC_KC[@]}" get pods -n "${COO_NS}" -l "app.kubernetes.io/instance=logging" -o wide 2>/dev/null || true
  fi
else
  echo "Warning: Deployment logging not found in ${COO_NS} within ${ROLLOUT_TIMEOUT}s — is Cluster Observability Operator installed and reconciling UIPlugins?" >&2
fi

echo "Done."
