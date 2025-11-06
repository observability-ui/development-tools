#!/bin/bash

echo "--- Cleanup Bundle installation ---"

operator-sdk cleanup cluster-observability-operator --namespace openshift-cluster-observability-operator
