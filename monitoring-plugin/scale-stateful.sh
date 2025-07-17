#!/bin/bash
statefulsets=$(oc get statefulsets -n openshift-monitoring -o custom-columns=":metadata.name" | tail -n +2)
if [ -z "$statefulsets" ]; then
    echo "No statefulsets found in openshift-monitoring namespace."
else
    for i in $statefulsets; do
        oc scale statefulset/$i --replicas=1 -n openshift-monitoring
    done
fi
