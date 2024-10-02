#!/bin/bash

# Prerequisites 
# 1) Must be logged in to an OpenShift cluster as a cluster adminstrator 

# Terminal output colors 
GREEN='\033[0;32m'
ENDCOLOR='\033[0m' # No Color
RED='\033[0;31m'

# Enviornment variables: Observability operator test images 
OPERATOR_BUNDLE=${OPERATOR_BUNDLE:="quay.io/gbernal/observability-operator-bundle:0.4.0-dev-tp"}
printf "\n${GREEN} OPERATOR_BUNDLE: $OPERATOR_BUNDLE ${ENDCOLOR}\n"

# OpenShift Version
OCP=$(oc version --output json | jq -r '.openshiftVersion')
OCP_VERSION="${OCP:0:4}"
printf "\n${GREEN} OCP version: $OCP_VERSION ${ENDCOLOR}\n"

# Resources for other Observability operator test image versions
OPERATOR_BUNDLE_V04=${OPERATOR_BUNDLE_V04:="quay.io/gbernal/observability-operator-bundle:0.4.0-dev-tp"}
OPERATOR_BUNDLE_V03=${OPERATOR_BUNDLE_V03:="quay.io/gbernal/observability-operator-bundle:0.3.0-ui-v1-10"}
OPERATOR_BUNDLE_V02=${OPERATOR_BUNDLE_V02:="quay.io/gbernal/observability-operator-bundle:0.2.0-dev-3"}

deploy_observability_operator(){
    echo "Deploying Observability Operator with $1"

    operator-sdk run bundle \
    $1 \
    --install-mode AllNamespaces \
    --namespace openshift-operators \
	--security-context-config restricted
}

deploy_dashboards() {
    (cd  ../dashboards && ./deploy-dashboards.sh )
    (cd  ../coo && oc apply -f ui-plugin-dashboards.yaml )
}

deploy_korrel8r(){
    printf "\n${GREEN} *** Deploying Korrel8r, Logging, Network Observability *** ${ENDCOLOR}\n"
    (cd  ../korrel8r && cd openshift && make operators && make resources)
    (cd  ../coo && oc apply -f ui-plugin-logging.yaml )
}

deploy_troubleshooting(){
    printf "\n${GREEN} *** Deploying Troubleshooting *** ${ENDCOLOR}\n"
    (cd  ../coo && oc apply -f ui-plugin-troubleshooting.yaml )
}

print(){
    echo
    echo $1 
    echo
}

print_title(){
    echo
    printf "${GREEN}*** $1 ***${ENDCOLOR}"
    echo
}

# Deploy UIPlugins and Observability Operator based on OpenShift Version 
if [[ $(bc <<< "$OCP_VERSION == 4.11") -eq 1 ]]; then
    print_title "Deploying OCP 4.11 compatabile resources..."
    print "COO: 0.2.0"
    print "UIPlugins: dashboards"

    deploy_observability_operator $OPERATOR_BUNDLE_V02
    deploy_dashboards
        
elif [[ $(bc <<< "$OCP_VERSION >= 4.12") -eq 1 ]] && [[ $(bc <<< "$OCP_VERSION <= 4.15") -eq 1 ]]; then
    print_title "Deploying OCP 4.12 - 4.15 compatible resources...  "
    print "COO/ObO: 0.3.0+ required! Image being deployed is $OPERATOR_BUNDLE"
    print "UIPlugins: dashboards, distributed tracing, logging"

    deploy_observability_operator $OPERATOR_BUNDLE
    deploy_korrel8r # UIPlugin and Resources for korrel8r, logging, troubleshooting, net observe  
    deploy_dashboards

elif [[ $(bc <<< "$OCP_VERSION >= 4.16") -eq 1 ]]; then
    print_title "Deploying OCP 4.16+ compatible resources..."
    print "COO/ObO: 0.3.0+ required! Image being deployed is $OPERATOR_BUNDLE"
    print "UIPlugins: dashboards, distributed tracing, logging, troubleshooting"

    deploy_observability_operator $OPERATOR_BUNDLE
    deploy_korrel8r   # UIPlugin and Resources for korrel8r, logging, net observe  
    deploy_troubleshooting
    deploy_dashboards

else
    print "OCP version not supported"
fi
