#!/usr/bin/env bash

set -e -o pipefail

up() {
    oc scale --replicas=1 -n openshift-monitoring deployment/cluster-monitoring-operator

    oc scale --replicas=1 -n openshift-monitoring deployment/monitoring-plugin
}

down() {
    # Set Cluster Monitoring Operator (CMO) to unmanged
    # Resource https://access.redhat.com/solutions/6548111
    oc patch clusterversion version --type json -p "$(cat disable-monitoring.yaml)"

    oc scale --replicas=0 -n openshift-monitoring deployment/cluster-monitoring-operator

    oc scale --replicas=0 -n openshift-monitoring deployment/monitoring-plugin
    # After scaling you can modify the CMO deployment spec to reference your image
    # https://github.com/openshift/cluster-monitoring-operator/blob/5d1fd1bb52eeb9b2f877c45de0cf93e2f9fffb95/manifests/0000_50_cluster-monitoring-operator_05-deployment.yaml#L76

}

if [[ "${1}" == "up" ]]; then
    up
elif [[ "${1}" == "down" ]]; then
    down
else
    echo "invalid parameter"
fi
