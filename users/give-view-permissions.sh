#!/usr/bin/env bash

set -e -o pipefail

UP_DOWN="${1}"
NAMESPACE="${2}"
USER="${3}"

up() {
    oc -n ${NAMESPACE} policy add-role-to-user view ${USER}
    oc -n ${NAMESPACE} policy add-role-to-user cluster-logging-application-view ${USER}
    oc -n ${NAMESPACE} policy add-role-to-user monitoring-rules-edit ${USER}
    oc -n ${NAMESPACE} policy add-role-to-user cluster-monitoring-view ${USER}
}

down() {
    oc -n ${NAMESPACE} policy remove-role-from-user view ${USER}
    oc -n ${NAMESPACE} policy remove-role-from-user cluster-logging-application-view ${USER}
    oc -n ${NAMESPACE} policy remove-role-from-user monitoring-rules-edit ${USER}
    oc -n ${NAMESPACE} policy remove-role-from-user cluster-monitoring-view ${USER}
}

if [[ "${UP_DOWN}" == "up" ]]; then
    up
elif [[ "${UP_DOWN}" == "down" ]]; then
    down
else
    echo "invalid parameter"
fi
