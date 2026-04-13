#!/bin/bash
# OpenShift distributed tracing: Tempo + OpenTelemetry operators, MinIO, TempoStack, collectors, sample apps.
# All Kubernetes YAML is embedded below (no external manifest directory).
#
# Env:
#   KUBECONFIG_PATH
#   COO_NS — namespace where the observability operator runs UI plugin Deployments (default openshift-cluster-observability-operator)
#   TEMPO_CHANNEL / OTEL_CHANNEL — default "auto" = PackageManifest defaultChannel
#   OPERATOR_INSTALL_TIMEOUT (default 900), ROLLOUT_TIMEOUT (default 600), OLM_POLL_INTERVAL (default 5)
#
# OLM waits use Subscription.status.currentCSV until CSV phase Succeeded.

set -euo pipefail

if [[ -n "${KUBECONFIG_PATH:-}" ]]; then
  OC_KC=(oc --kubeconfig "${KUBECONFIG_PATH}")
else
  OC_KC=(oc)
fi

OPERATOR_INSTALL_TIMEOUT="${OPERATOR_INSTALL_TIMEOUT:-900}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-600}"
OLM_POLL_INTERVAL="${OLM_POLL_INTERVAL:-5}"

NS_TRACING="${NS_TRACING:-openshift-tracing}"
NS_TEMPO_OP="${NS_TEMPO_OP:-openshift-tempo-operator}"
NS_OTEL_OP="${NS_OTEL_OP:-openshift-opentelemetry-operator}"
COO_NS="${COO_NS:-openshift-cluster-observability-operator}"
TEMPO_CHANNEL="${TEMPO_CHANNEL:-auto}"
OTEL_CHANNEL="${OTEL_CHANNEL:-auto}"

resolve_channel_from_catalog() {
  local pkg=$1
  local fb=${2:-stable}
  local ch
  ch=$("${OC_KC[@]}" get packagemanifest "$pkg" -n openshift-marketplace -o jsonpath='{.status.defaultChannel}' 2>/dev/null || true)
  if [[ -n "$ch" ]]; then
    echo "$ch"
  else
    echo "$fb"
  fi
}

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
  echo "OLM repair: ${sub_name} (${ns}) references missing CSV ${installed}; deleting Subscription + InstallPlans"
  "${OC_KC[@]}" delete subscriptions.operators.coreos.com "$sub_name" -n "$ns" --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
  if [[ -n "${installplan_label_key}" ]]; then
    "${OC_KC[@]}" delete installplan -n "$ns" -l "${installplan_label_key}" --ignore-not-found 2>/dev/null || true
  fi
  sleep 3
}

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
    sleep 5
  done
  echo "Timeout: $msg" >&2
  return 1
}

# Do not use plain `oc get deploy -n ... -o name` as the wait predicate: it exits 0 even when the list is empty.
tempo_gateway_deploy_present() {
  "${OC_KC[@]}" get deploy -n "$NS_TRACING" -o name 2>/dev/null | grep -qE 'platform-gateway|tempo-.*-gateway'
}

wait_csv_from_subscription() {
  local ns=$1
  local sub_name=$2
  local deadline=$(( $(date +%s) + OPERATOR_INSTALL_TIMEOUT ))
  local last_log=$(( $(date +%s) ))
  echo "Waiting for Subscription ${sub_name} CSV Succeeded in ${ns}"
  while (( $(date +%s) < deadline )); do
    local csv_name phase
    csv_name=$("${OC_KC[@]}" get subscriptions.operators.coreos.com "$sub_name" -n "$ns" -o jsonpath='{.status.currentCSV}' 2>/dev/null || true)
    if [[ -n "$csv_name" ]] && "${OC_KC[@]}" get csv "$csv_name" -n "$ns" &>/dev/null; then
      phase=$("${OC_KC[@]}" get csv "$csv_name" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || true)
      if [[ "$phase" == "Succeeded" ]]; then
        echo "CSV ready: ${csv_name}"
        return 0
      fi
      if [[ "$phase" == "Failed" ]]; then
        echo "CSV ${csv_name} phase=Failed in ${ns}" >&2
        "${OC_KC[@]}" describe csv "$csv_name" -n "$ns" 2>/dev/null | tail -50 >&2 || true
        return 1
      fi
    fi
    local now=$(( $(date +%s) ))
    if (( now - last_log >= 60 )); then
      last_log=$now
      echo "... still waiting (${sub_name}): currentCSV=${csv_name:-<none>} phase=${phase:-n/a}"
      "${OC_KC[@]}" get subscriptions.operators.coreos.com "$sub_name" -n "$ns" -o jsonpath='{range .status.conditions[*]}{.type}={.message}{"\n"}{end}' 2>/dev/null || true
    fi
    sleep "${OLM_POLL_INTERVAL}"
  done
  echo "Timeout waiting for Subscription ${sub_name} CSV in ${ns}" >&2
  "${OC_KC[@]}" get subscriptions.operators.coreos.com "$sub_name" -n "$ns" -o yaml 2>/dev/null | tail -40 >&2 || true
  "${OC_KC[@]}" get csv -n "$ns" -o wide 2>/dev/null || true
  return 1
}

if [[ "${TEMPO_CHANNEL}" == "auto" ]]; then
  TEMPO_CHANNEL=$(resolve_channel_from_catalog tempo-product)
fi
if [[ "${OTEL_CHANNEL}" == "auto" ]]; then
  OTEL_CHANNEL=$(resolve_channel_from_catalog opentelemetry-product)
fi
echo "Subscription channels: tempo-product=${TEMPO_CHANNEL}, opentelemetry-product=${OTEL_CHANNEL}"

repair_orphaned_subscription "$NS_TEMPO_OP" tempo-product 'operators.coreos.com/tempo-product.openshift-tempo-operator='
repair_orphaned_subscription "$NS_OTEL_OP" opentelemetry-product 'operators.coreos.com/opentelemetry-product.openshift-opentelemetry-operator='

echo "=== Apply openshift-tracing Project ==="
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: project.openshift.io/v1
kind: Project
metadata:
  name: openshift-tracing
EOF

echo "=== Apply Tempo + OpenTelemetry operator Projects, OperatorGroups, Subscriptions ==="
cat <<EOF | "${OC_KC[@]}" apply -f -
apiVersion: project.openshift.io/v1
kind: Project
metadata:
  name: openshift-tempo-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-tempo-operator
  namespace: openshift-tempo-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: tempo-product
  namespace: openshift-tempo-operator
spec:
  channel: ${TEMPO_CHANNEL}
  installPlanApproval: Automatic
  name: tempo-product
  source: redhat-operators
  sourceNamespace: openshift-marketplace
---
apiVersion: project.openshift.io/v1
kind: Project
metadata:
  name: openshift-opentelemetry-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-opentelemetry-operator
  namespace: openshift-opentelemetry-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: opentelemetry-product
  namespace: openshift-opentelemetry-operator
spec:
  channel: ${OTEL_CHANNEL}
  installPlanApproval: Automatic
  name: opentelemetry-product
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

echo "=== Wait for Tempo + OpenTelemetry operator CSVs (parallel) ==="
wait_csv_from_subscription "$NS_TEMPO_OP" tempo-product &
_pid1=$!
wait_csv_from_subscription "$NS_OTEL_OP" opentelemetry-product &
_pid2=$!
_ec=0
wait $_pid1 || _ec=1
wait $_pid2 || _ec=1
if ((_ec != 0)); then
  exit 1
fi

echo "=== Apply MinIO (openshift-tracing) ==="
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    app.kubernetes.io/name: minio
  name: minio
  namespace: openshift-tracing
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: openshift-tracing
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
              mkdir -p /storage/tempo && \
              minio server /storage
          env:
            - name: MINIO_ACCESS_KEY
              value: tempo
            - name: MINIO_SECRET_KEY
              value: supersecret
          image: minio/minio
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
kind: Service
metadata:
  name: minio
  namespace: openshift-tracing
spec:
  ports:
    - port: 9000
      protocol: TCP
      targetPort: 9000
  selector:
    app.kubernetes.io/name: minio
  type: ClusterIP
---
apiVersion: v1
kind: Secret
metadata:
  name: minio
  namespace: openshift-tracing
stringData:
  endpoint: http://minio:9000
  bucket: tempo
  access_key_id: tempo
  access_key_secret: supersecret
type: Opaque
EOF

echo "Wait for MinIO rollout (${NS_TRACING})"
wait_until "deployment minio in ${NS_TRACING}" "${ROLLOUT_TIMEOUT}" \
  "${OC_KC[@]}" get deployment minio -n "$NS_TRACING" -o name &>/dev/null
"${OC_KC[@]}" rollout status deployment/minio -n "$NS_TRACING" --timeout="${ROLLOUT_TIMEOUT}s"

echo "=== Apply user workload monitoring ConfigMap (cluster-admin may be required) ==="
if ! "${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
EOF
then
  echo "Warning: cluster-monitoring-config apply failed (RBAC?); continuing." >&2
fi

echo "=== Apply TempoStack + trace reader RBAC ==="
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: tempo.grafana.com/v1alpha1
kind:  TempoStack
metadata:
  name: platform
  namespace: openshift-tracing
spec:
  storage:
    secret:
      name: minio
      type: s3
  storageSize: 1Gi
  tenants:
    mode: openshift
    authentication:
    - tenantName: platform
      tenantId: 1610b0c3-c509-4592-a256-a1871353dbfa
    - tenantName: user
      tenantId: 1610b0c3-c509-4592-a256-a1871353dbfb
  observability:
    tracing:
      otlp_http_endpoint: http://platform-collector.openshift-tracing:4318
      sampling_fraction: "1"
  template:
    gateway:
      enabled: true
    queryFrontend:
      jaegerQuery:
        enabled: true
        monitorTab:
          enabled: true
          prometheusEndpoint: https://thanos-querier.openshift-monitoring.svc.cluster.local:9092
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: traces-reader-platform
rules:
- apiGroups: [tempo.grafana.com]
  resources: [platform]
  resourceNames: [traces]
  verbs: [get]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: traces-reader-platform
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: traces-reader-platform
subjects:
- kind: Group
  apiGroup: rbac.authorization.k8s.io
  name: system:authenticated
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: traces-reader-user
rules:
- apiGroups: [tempo.grafana.com]
  resources: [user]
  resourceNames: [traces]
  verbs: [get]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: traces-reader-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: traces-reader-user
subjects:
- kind: Group
  apiGroup: rbac.authorization.k8s.io
  name: system:authenticated
EOF

echo "Wait for Tempo gateway (stack: platform)"
wait_until "Tempo gateway deployment in ${NS_TRACING}" "${ROLLOUT_TIMEOUT}" tempo_gateway_deploy_present
_gw=$("${OC_KC[@]}" get deploy -n "$NS_TRACING" -o name 2>/dev/null | grep -E 'platform-gateway|tempo-.*-gateway' | head -1 || true)
if [[ -n "${_gw}" ]]; then
  "${OC_KC[@]}" rollout status "${_gw}" -n "$NS_TRACING" --timeout="${ROLLOUT_TIMEOUT}s"
else
  echo "Warning: gateway deployment name not matched; listing deployments:" >&2
  "${OC_KC[@]}" get deploy -n "$NS_TRACING" 2>/dev/null || true
fi

echo "=== Apply OpenTelemetryCollectors (platform) + RBAC ==="
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: platform
  namespace: openshift-tracing
spec:
  observability:
    metrics:
      enableMetrics: true
  config:
    extensions:
      bearertokenauth:
        filename: /var/run/secrets/kubernetes.io/serviceaccount/token
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      jaeger:
        protocols:
          thrift_compact:
            endpoint: 0.0.0.0:6831
    connectors:
      spanmetrics:
        metrics_flush_interval: 5s
        dimensions:
        - name: k8s.namespace.name
    processors:
      k8sattributes: {}
    exporters:
      otlp:
        endpoint: tempo-platform-gateway.openshift-tracing.svc.cluster.local:8090
        tls:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt
        auth:
          authenticator: bearertokenauth
        headers:
          X-Scope-OrgID: platform
      prometheus:
        endpoint: 0.0.0.0:8889
        add_metric_suffixes: false
        resource_to_telemetry_conversion:
          enabled: true
    service:
      extensions: [bearertokenauth]
      pipelines:
        traces:
          receivers: [otlp, jaeger]
          processors: [k8sattributes]
          exporters: [otlp, spanmetrics]
        metrics:
          receivers: [spanmetrics]
          processors: []
          exporters: [prometheus]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: openshift-tracing-platform-collector
rules:
- apiGroups: [""]
  resources: ["namespaces", "pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["replicasets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: openshift-tracing-platform-collector
roleRef:
  kind: ClusterRole
  name: openshift-tracing-platform-collector
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: platform-collector
  namespace: openshift-tracing
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: traces-writer-platform
rules:
- apiGroups: [tempo.grafana.com]
  resources: [platform]
  resourceNames: [traces]
  verbs: [create]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: traces-writer-platform
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: traces-writer-platform
subjects:
- kind: ServiceAccount
  name: platform-collector
  namespace: openshift-tracing
EOF

echo "=== Apply OpenTelemetryCollectors (user) + RBAC ==="
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: user
  namespace: openshift-tracing
spec:
  observability:
    metrics:
      enableMetrics: true
  config:
    extensions:
      bearertokenauth:
        filename: /var/run/secrets/kubernetes.io/serviceaccount/token
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      jaeger:
        protocols:
          thrift_compact:
            endpoint: 0.0.0.0:6831
    connectors:
      spanmetrics:
        metrics_flush_interval: 5s
        dimensions:
        - name: k8s.namespace.name
    processors:
      k8sattributes: {}
    exporters:
      otlp:
        endpoint: tempo-platform-gateway.openshift-tracing.svc.cluster.local:8090
        tls:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt
        auth:
          authenticator: bearertokenauth
        headers:
          X-Scope-OrgID: user
      prometheus:
        endpoint: 0.0.0.0:8889
        add_metric_suffixes: false
        resource_to_telemetry_conversion:
          enabled: true
    service:
      extensions: [bearertokenauth]
      pipelines:
        traces:
          receivers: [otlp, jaeger]
          processors: [k8sattributes]
          exporters: [otlp, spanmetrics]
        metrics:
          receivers: [spanmetrics]
          processors: []
          exporters: [prometheus]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: openshift-tracing-user-collector
rules:
- apiGroups: [""]
  resources: ["namespaces", "pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["replicasets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: openshift-tracing-user-collector
roleRef:
  kind: ClusterRole
  name: openshift-tracing-user-collector
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: user-collector
  namespace: openshift-tracing
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: traces-writer-user
rules:
- apiGroups: [tempo.grafana.com]
  resources: [user]
  resourceNames: [traces]
  verbs: [create]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: traces-writer-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: traces-writer-user
subjects:
- kind: ServiceAccount
  name: user-collector
  namespace: openshift-tracing
EOF

echo "Wait for collector deployments (platform-collector, user-collector)"
wait_until "deployment platform-collector in ${NS_TRACING}" "${ROLLOUT_TIMEOUT}" \
  "${OC_KC[@]}" get deployment platform-collector -n "$NS_TRACING" -o name &>/dev/null
"${OC_KC[@]}" rollout status deployment/platform-collector -n "$NS_TRACING" --timeout="${ROLLOUT_TIMEOUT}s"

wait_until "deployment user-collector in ${NS_TRACING}" "${ROLLOUT_TIMEOUT}" \
  "${OC_KC[@]}" get deployment user-collector -n "$NS_TRACING" -o name &>/dev/null
"${OC_KC[@]}" rollout status deployment/user-collector -n "$NS_TRACING" --timeout="${ROLLOUT_TIMEOUT}s"

echo "=== Apply sample tracing app Projects ==="
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: project.openshift.io/v1
kind: Project
metadata:
  name: tracing-app-k6
---
apiVersion: project.openshift.io/v1
kind: Project
metadata:
  name: tracing-app-hotrod
---
apiVersion: project.openshift.io/v1
kind: Project
metadata:
  name: tracing-app-telemetrygen
EOF

echo "=== Apply hotrod, k6, telemetrygen ==="
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/name: hotrod
  name: hotrod
  namespace: tracing-app-hotrod
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: hotrod
  template:
    metadata:
      labels:
        app.kubernetes.io/name: hotrod
    spec:
      containers:
      - image: jaegertracing/example-hotrod:1.46
        name: hotrod
        args:
        - all
        - --otel-exporter=otlp
        env:
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: http://user-collector.openshift-tracing:4318
        ports:
        - containerPort: 8080
          name: frontend
        - containerPort: 8081
          name: customer
        - containerPort: 8083
          name: route
        resources:
          limits:
            cpu: 100m
            memory: 100M
          requests:
            cpu: 100m
            memory: 100M
---
apiVersion: v1
kind: Service
metadata:
  name: hotrod
  namespace: tracing-app-hotrod
spec:
  selector:
    app.kubernetes.io/name: hotrod
  ports:
  - name: frontend
    port: 8080
    targetPort: frontend
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: hotrod
  namespace: tracing-app-hotrod
spec:
  to:
    kind: Service
    name: hotrod
EOF

"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/name: k6-tracing
  name: k6-tracing
  namespace: tracing-app-k6
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: k6-tracing
  template:
    metadata:
      labels:
        app.kubernetes.io/name: k6-tracing
    spec:
      containers:
      - name: k6-tracing
        image: ghcr.io/grafana/xk6-client-tracing:v0.0.5
        env:
        - name: ENDPOINT
          value: user-collector.openshift-tracing:4317
EOF

"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/name: telemetrygen
  name: telemetrygen
  namespace: tracing-app-telemetrygen
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: telemetrygen
  template:
    metadata:
      labels:
        app.kubernetes.io/name: telemetrygen
    spec:
      containers:
      - name: telemetrygen1
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.105.0
        args:
          - traces
          - --otlp-endpoint=user-collector.openshift-tracing:4317
          - --otlp-insecure
          - --duration=1h
          - --service=good_service
          - --rate=3
          - --child-spans=2
      - name: telemetrygen2
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.105.0
        args:
          - traces
          - --otlp-endpoint=user-collector.openshift-tracing:4317
          - --otlp-insecure
          - --duration=1h
          - --service=faulty_service
          - --rate=2
          - --child-spans=1
          - --status-code=Error
EOF

echo "Wait for sample app rollouts (non-fatal if an image is slow to pull)"
_rollout_sample() {
  local ns=$1 dep=$2
  if wait_until "deployment ${dep} in ${ns}" 120 \
    "${OC_KC[@]}" get deployment "${dep}" -n "${ns}" -o name &>/dev/null; then
    "${OC_KC[@]}" rollout status "deployment/${dep}" -n "${ns}" --timeout="${ROLLOUT_TIMEOUT}s" || true
  else
    echo "Warning: ${dep} not found in ${ns} yet (check apply / image pull)." >&2
  fi
}
_rollout_sample tracing-app-hotrod hotrod
_rollout_sample tracing-app-k6 k6-tracing
_rollout_sample tracing-app-telemetrygen telemetrygen

echo "=== Apply Distributed Tracing UIPlugin (Observe → Tracing) ==="
"${OC_KC[@]}" apply -f - <<'EOF'
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: distributed-tracing
spec:
  type: DistributedTracing
EOF

echo "Wait for UIPlugin Available and console plugin workload in ${COO_NS}"
if "${OC_KC[@]}" wait uiplugin distributed-tracing --for=condition=Available --timeout="${ROLLOUT_TIMEOUT}s" 2>/dev/null; then
  echo "UIPlugin distributed-tracing: condition Available"
else
  echo "Note: oc wait UIPlugin Available skipped, failed, or timed out; checking Deployment/Pods in ${COO_NS}." >&2
fi

if wait_until "deployment distributed-tracing in ${COO_NS}" "${ROLLOUT_TIMEOUT}" \
  "${OC_KC[@]}" get deployment distributed-tracing -n "${COO_NS}" -o name &>/dev/null; then
  "${OC_KC[@]}" rollout status deployment/distributed-tracing -n "${COO_NS}" --timeout="${ROLLOUT_TIMEOUT}s"
  if "${OC_KC[@]}" wait pod -n "${COO_NS}" \
    -l "app.kubernetes.io/instance=distributed-tracing,app.kubernetes.io/part-of=UIPlugin" \
    --for=condition=Ready --timeout="${ROLLOUT_TIMEOUT}s" 2>/dev/null; then
    echo "Distributed Tracing plugin pod(s) Ready (${COO_NS})"
  else
    echo "Warning: pod Ready wait failed; current pods:" >&2
    "${OC_KC[@]}" get pods -n "${COO_NS}" -l "app.kubernetes.io/instance=distributed-tracing" -o wide 2>/dev/null || true
  fi
else
  echo "Warning: Deployment distributed-tracing not found in ${COO_NS} within ${ROLLOUT_TIMEOUT}s — is Cluster Observability Operator installed and reconciling UIPlugins?" >&2
fi

echo "Done (z_tracing.sh)."
