#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prompt user for namespace
read -p "Enter the namespace to apply dashboards and datasources: " NAMESPACE

if [ -z "$NAMESPACE" ]; then
    echo "Error: Namespace cannot be empty."
    exit 1
fi

# Ask if user wants to create the namespace if it doesn't exist
read -p "Create namespace '$NAMESPACE' if it doesn't exist? (y/n): " CREATE_NS

if [ "$CREATE_NS" = "y" ] || [ "$CREATE_NS" = "Y" ]; then
    oc new-project "$NAMESPACE" 2>/dev/null || oc project "$NAMESPACE"
else
    oc project "$NAMESPACE"
fi

echo ""
echo "Applying dashboards and datasources to namespace: $NAMESPACE"
echo "============================================================"

# List of YAML files to apply
YAML_FILES=(
    "openshift-cluster-sample-dashboard.yaml"
    "perses-dashboard-sample.yaml"
    "prometheus-overview-variables.yaml"
    "thanos-compact-overview-1var.yaml"
    "perses-datasource-sample.yaml"
    "thanos-querier-datasource.yaml"
)

# Apply each file with namespace replaced
for file in "${YAML_FILES[@]}"; do
    echo "Applying $file..."
    sed "s/namespace: perses-dev/namespace: $NAMESPACE/g" "$SCRIPT_DIR/$file" | oc apply -f -
done

echo ""
echo "Done! All resources applied to namespace: $NAMESPACE"
