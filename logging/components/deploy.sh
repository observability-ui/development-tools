#!/usr/bin/env bash
# Prerequisites: ready Loki and Logging operators; COO if DEPLOY_UI_PLUGIN=true.
# Fresh disposable clusters only: shared resources are reapplied, not migrated.
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

# Validate options before changing the cluster.
data_model=${1:?Usage: deploy.sh otel|viaq}
deploy_ui_plugin=${DEPLOY_UI_PLUGIN:-true}
storage_class=${STORAGE_CLASS:-}

case "$data_model" in
    otel|viaq) ;;
    *)
        echo 'Expected otel or viaq' >&2
        exit 1
        ;;
esac

case "$deploy_ui_plugin" in
    true|false) ;;
    *)
        echo 'DEPLOY_UI_PLUGIN must be true or false' >&2
        exit 1
        ;;
esac

# Loki needs an explicit class; MinIO uses the cluster default.
if [[ -z "$storage_class" ]]; then
    default_class_query='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'
    default_classes=$(oc get storageclass -o "jsonpath=$default_class_query")
    read -r -a defaults <<< "$default_classes"

    if [[ ${#defaults[@]} -ne 1 ]]; then
        echo 'Set STORAGE_CLASS; expected exactly one default StorageClass.' >&2
        exit 1
    fi
    storage_class=${defaults[0]}
fi
oc get storageclass "$storage_class" >/dev/null

echo "Deploying $data_model logging"

echo 'Deploying MinIO'
oc apply -f minio.yaml
oc rollout status deployment/minio -n minio --timeout=5m

echo 'Deploying LokiStack'
sed "s|gp3-csi|${storage_class}|g" lokistack.yaml | oc apply -f -
oc wait lokistack/logging-loki -n openshift-logging \
    --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True --timeout=10m

echo 'Configuring collector permissions'
oc apply -f roles.yaml
oc create sa collector -n openshift-logging --dry-run=client -o yaml | oc apply -f -

collector_roles=(
    logging-collector-logs-writer
    collect-application-logs
    collect-audit-logs
    collect-infrastructure-logs
    cluster-logging-write-application-logs
    cluster-logging-write-audit-logs
    cluster-logging-write-infrastructure-logs
)
for role in "${collector_roles[@]}"; do
    oc adm policy add-cluster-role-to-user "$role" -z collector -n openshift-logging
done

echo 'Deploying ClusterLogForwarder'
oc apply -f "${data_model}_cluster_log_forwarder.yaml"
oc wait clusterlogforwarder.observability.openshift.io/collector -n openshift-logging \
    --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True --timeout=5m

if [[ "$deploy_ui_plugin" == true ]]; then
    echo 'Deploying logging UIPlugin'
    oc apply -f ui_plugin.yaml
fi
