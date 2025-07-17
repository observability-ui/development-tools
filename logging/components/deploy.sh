# OCP 4.18
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/logging/logging-6-2#quick-start-opentelemetry_logging-6x-6.2
# Prerequisites:
# Install the :
#   [] Red Hat OpenShift Logging Operator,
#   [] Loki Operator, and
#   [] Cluster Observability Operator (COO) from OperatorHub.

DATA_MODEL=$1
echo " ** Data Model used wil be : $DATA_MODEL ** "
echo " ========================================== "

echo " ========= Minio Configuration ============ "
oc apply -f minio.yaml

echo " ========= LokiStack Configuration ======== "
oc apply -f lokistack.yaml

# collector service account and RBAC
echo " ======= Collector Configurguration ======= "
oc create sa collector -n openshift-logging
oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z collector
oc project openshift-logging
oc adm policy add-cluster-role-to-user collect-application-logs -z collector
oc adm policy add-cluster-role-to-user collect-audit-logs -z collector
oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z collector

echo " ==== UI-Plugin Logging Configuration ===== "
oc apply -f ui_plugin.yaml

echo " ======= ClusterLogForwarder Config ========= "
if [ "$DATA_MODEL" == "otel" ]; then
    oc apply -f otel_cluster_log_forwarder.yaml
else
    oc apply -f viaq_cluster_log_forwarder.yaml
fi
