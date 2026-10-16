#!/usr/bin/env bash
# Installs the Loki and Cluster Logging operators via OLM, test object storage
# (MinIO), the logging-loki LokiStack, viaq log collection and a tiny log
# generator.
# To run the UI run make start-mcp-console in monitoring-plugin. Not a migration
# or rollback tool: it targets a fresh cluster and refuses resources it did
# not create. Rerunning after a partial failure is safe.
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
loki_namespace=openshift-operators-redhat
logging_namespace=openshift-logging
channel=${LOGGING_CHANNEL:-stable-6.5}
storage_class=${STORAGE_CLASS:-}
# Applied by this script to the resources it creates (the shared manifests
# stay flow-neutral); foreign, unmarked resources refuse.
marker=development-tools.observability/merged-logging-test

usage() {
  echo "Usage: $0"
  echo 'Sets up the logging stack (Loki and Cluster Logging operators, MinIO,'
  echo 'LokiStack, collection, test logs) on a fresh disposable OCP cluster.'
  echo 'Then run the merged-logging UI locally: make start-mcp-console in'
  echo 'the monitoring-plugin checkout.'
  echo "LOGGING_CHANNEL (default $channel), STORAGE_CLASS (default: the cluster's"
  echo 'single default StorageClass; the shipped LokiStack manifest assumes'
  echo 'gp3-csi on AWS).'
}
case ${1:-} in
'') ;;
-h | --help)
  usage
  exit 0
  ;;
*)
  usage >&2
  exit 1
  ;;
esac

command -v oc >/dev/null || {
  echo 'oc is required' >&2
  exit 1
}
oc whoami >/dev/null
trap 'echo "Failed at line $LINENO. Fix the cause and rerun; steps are idempotent." >&2' ERR

# The LokiStack manifest pins gp3-csi; resolve what to substitute for it. The
# MinIO PVC has no storageClassName and always uses the cluster default.
if [[ -z "$storage_class" ]]; then
  mapfile -t defaults < <(oc get storageclass \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' |
    awk '$2 == "true" {print $1}')
  ((${#defaults[@]} == 1)) || {
    echo 'STORAGE_CLASS must be set; autodetection needs exactly one default StorageClass.' >&2
    printf 'Found: %s\n' "${defaults[@]:-none}" >&2
    exit 1
  }
  storage_class=${defaults[0]}
fi
oc get storageclass "$storage_class" >/dev/null

# Refuse resources this setup did not create; marked ones come from an earlier
# run and are safe to reapply. A missing resource type means a fresh cluster.
refuse_foreign() { # kind name namespace description
  local ns_args=() resource
  [[ -n "$3" ]] && ns_args=(-n "$3")
  # A missing kind or object means a fresh cluster; oc exits nonzero for
  # unknown kinds even with --ignore-not-found, so tolerate that here.
  resource=$(oc get "$1" "$2" "${ns_args[@]}" --ignore-not-found -o name 2>/dev/null || true)
  if [[ -n "$resource" ]]; then
    # Select by the marker label: oc's jsonpath cannot quote label keys that
    # contain dots or slashes, so reading the label directly always looks empty.
    oc get "$1" -l "$marker=true" "${ns_args[@]}" -o name 2>/dev/null | grep -qxF "$resource" || {
      echo "Existing $4 not created by this setup; refusing to overwrite it. Use a fresh cluster." >&2
      exit 1
    }
  fi
}
refuse_foreign namespace minio '' 'MinIO namespace'
refuse_foreign lokistack logging-loki "$logging_namespace" 'LokiStack'
refuse_foreign clusterlogforwarder collector "$logging_namespace" 'log forwarder'

installed_csv() {
  oc get subscriptions.operators.coreos.com "$1" -n "$2" \
    -o jsonpath='{.status.installedCSV}'
}

install_operator() { # package namespace channel
  local package=$1 namespace=$2 release_channel=$3 csv='' existing_channel
  oc create namespace "$namespace" --dry-run=client -o yaml | oc apply -f -
  oc label namespace "$namespace" openshift.io/cluster-monitoring=true --overwrite
  if [[ -z "$(oc get operatorgroups -n "$namespace" -o name)" ]]; then
    oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ${package}
  namespace: ${namespace}
spec: {}
EOF
  fi
  if [[ -n "$(oc get subscriptions.operators.coreos.com "$package" -n "$namespace" --ignore-not-found -o name)" ]]; then
    existing_channel=$(oc get subscriptions.operators.coreos.com "$package" -n "$namespace" -o jsonpath='{.spec.channel}')
    [[ "$existing_channel" == "$release_channel" ]] || {
      echo "$package uses $existing_channel, expected $release_channel; refusing a channel change" >&2
      return 1
    }
  else
    # No ROLEARN: this test uses static MinIO credentials, not AWS STS.
    oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${package}
  namespace: ${namespace}
spec:
  channel: ${release_channel}
  installPlanApproval: Automatic
  name: ${package}
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
  fi
  for _ in {1..120}; do
    csv=$(installed_csv "$package" "$namespace")
    [[ -n "$csv" ]] && break
    sleep 5
  done
  [[ -n "$csv" ]] || {
    echo "Timed out waiting for $package CSV" >&2
    return 1
  }
  oc wait "csv/$csv" -n "$namespace" --for=jsonpath='{.status.phase}'=Succeeded --timeout=10m
}

install_operator loki-operator "$loki_namespace" "$channel"
install_operator cluster-logging "$logging_namespace" "$channel"

oc apply -f "$root/components/minio.yaml"
oc label namespace minio "$marker=true" --overwrite
oc rollout status deployment/minio -n minio --timeout=5m
sed "s|gp3-csi|${storage_class}|g" "$root/components/lokistack.yaml" | oc apply -f -
oc label lokistack logging-loki -n "$logging_namespace" "$marker=true" --overwrite
# jsonpath form: oc wait errors immediately on condition/Ready when the
# condition is not populated yet on a freshly created resource.
oc wait lokistack/logging-loki -n "$logging_namespace" \
  --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True --timeout=10m

oc create serviceaccount collector -n "$logging_namespace" --dry-run=client -o yaml | oc apply -f -
for role in logging-collector-logs-writer collect-application-logs collect-infrastructure-logs; do
  oc adm policy add-cluster-role-to-user "$role" -z collector -n "$logging_namespace"
done
oc get configmap openshift-service-ca.crt -n "$logging_namespace" >/dev/null
oc apply -f "$root/components/viaq_cluster_log_forwarder.yaml"
oc label clusterlogforwarder.observability.openshift.io collector -n "$logging_namespace" "$marker=true" --overwrite
oc wait clusterlogforwarder.observability.openshift.io/collector -n "$logging_namespace" \
  --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True --timeout=5m

# A tiny application gives QE a known message to search for, without extra fixtures.
oc apply -f "$root/random-logs-generator-deployment.yaml"
oc rollout status deployment/log-generator -n merged-logging-test --timeout=5m

echo 'Logging stack is ready. Run the merged-logging UI locally from the'
echo 'monitoring-plugin checkout (make start-mcp-console), open Observe >'
echo 'Logs, select Application / ViaQ and namespace merged-logging-test, then'
echo 'search for merged-logging-test.'
