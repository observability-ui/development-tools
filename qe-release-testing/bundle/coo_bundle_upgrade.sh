#!/bin/bash

echo "--- Bundle Upgrade ---"

# 1. Patch the Scheduler
echo "Patching Scheduler to enable masters schedulable..."
kubectl patch Scheduler cluster --type='json' -p '[{ "op": "replace", "path": "/spec/mastersSchedulable", "value": true }]'

# 2. Get the bundle image
read -p 'Enter the full bundle image (e.g., quay.io/...): ' bundle
echo "Using bundle: ${bundle}"

# --- First Question: Quay or Stage ---
echo
echo "Is it a Quay or Stage bundle?"
echo "a) quay b) stage"

while true; do
  read -p "Enter your choice (a or b): " choice
  case $choice in
    a|b)
      break
      ;;
    *)
      echo "Invalid input. Please enter a or b."
      ;;
  esac
done

# Translate choice to index (1 for 'a' or 2 for 'b')
choice_index=$(( $(echo "$choice" | tr 'ab' '12') ))

oc project openshift-cluster-observability-operator

# Apply ImageDigestMirrorSet (must be flush left)
if [ "$choice_index" -eq 1 ]; then
  # quay
  echo "Applying ImageDigestMirrorSet for Quay..."
  oc apply -f - <<EOF
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: idms-coo
spec:
  imageDigestMirrors:
  - mirrors:
    - quay.io/redhat-user-workloads/cluster-observabilit-tenant/cluster-observability-operator
    source: registry.redhat.io/cluster-observability-operator
EOF
# The EOF above MUST be flush left!
else
  # stage
  echo "Applying ImageDigestMirrorSet for Stage..."
  oc apply -f - <<EOF
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: idms-coo
spec:
  imageDigestMirrors:
  - mirrors:
    - registry.stage.redhat.io
    source: registry.redhat.io
EOF
# The EOF above MUST be flush left!
fi

# --- Second Question: OCP Version ---
echo
echo "Which OCP version?"
echo "a) 4.12 to 4.18 b) 4.19+"

while true; do
  read -p "Enter your choice (a or b): " choice
  case $choice in
    a|b)
      break
      ;;
    *)
      echo "Invalid input. Please enter a or b."
      ;;
  esac
done

# Translate choice to index (1 for 'a' or 2 for 'b')
choice_index=$(( $(echo "$choice" | tr 'ab' '12') ))

# Run the bundle
if [ "$choice_index" -eq 1 ]; then
  echo "Running bundle for OCP 4.12-4.18..."
  operator-sdk run bundle-upgrade "${bundle}" --install-mode AllNamespaces
else
  echo "Running bundle for OCP 4.19+ (with restricted security context)..."
  operator-sdk run bundle-upgrade "${bundle}" --install-mode AllNamespaces --security-context-config restricted
fi

exit 0