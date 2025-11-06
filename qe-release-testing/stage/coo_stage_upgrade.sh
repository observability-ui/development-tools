#!/bin/bash
echo COO install through FBC

kubectl patch Scheduler cluster --type='json' -p '[{ "op": "replace", "path": "/spec/mastersSchedulable", "value": true }]'

read -p 'fbc_image ' fbc_image

fbc_image=$fbc_image

oc project openshift-cluster-observability-operator

oc apply -f - <<EOF
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  annotations:
  name: observability-operator
  namespace: openshift-marketplace
spec:
  displayName: coo-fbc
  icon:
    base64data: ""
    mediatype: ""
  image: ${fbc_image}
  sourceType: grpc
  grpcPodConfig:
    securityContextConfig: restricted
  updateStrategy:
    registryPoll:
      interval: 1m0s
EOF

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

oc apply -f - <<EOF
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  labels:
    operators.coreos.com/observability-operator.openshift-operators: ""
  name: cluster-observability-operator
  namespace: openshift-cluster-observability-operator
spec:
  channel: stable
  installPlanApproval: Automatic
  name: cluster-observability-operator
  source: observability-operator
  sourceNamespace: openshift-marketplace
EOF

oc project openshift-cluster-observability-operator