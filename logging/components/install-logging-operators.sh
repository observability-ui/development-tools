#!/usr/bin/env bash
# Install Loki and Logging operators on a fresh disposable cluster.
# Existing subscriptions must use LOGGING_CHANNEL; COO is not needed for local UI testing.
set -Eeuo pipefail

command -v oc >/dev/null
oc whoami >/dev/null
loki_namespace=openshift-operators-redhat
logging_namespace=openshift-logging
channel=${LOGGING_CHANNEL:-stable-6.5}

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

