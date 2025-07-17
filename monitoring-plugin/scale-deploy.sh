#!/bin/bash

deployments=$(oc get deployment -n openshift-monitoring -o custom-columns=":metadata.name" | tail -n +2) # Get deployment names, excluding the header

if [ -z "$deployments" ]; then
    echo "No deployments found in openshift-monitoring namespace."
else
    for i in $deployments; do
        oc scale deployment/$i --replicas=1 -n openshift-monitoring
    done
fi
