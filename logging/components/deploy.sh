# Logging 6.3
# https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.3/html/configuring_logging/configuring-log-forwarding#setting-up-log-collection_configuring-log-forwarding
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

echo " ========= Roles Configuration ======== "
oc apply -f roles.yaml

# collector service account and RBAC
echo " ======= Collector Configurguration ======= "
oc create sa collector -n openshift-logging
oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z collector
oc project openshift-logging
oc adm policy add-cluster-role-to-user collect-application-logs -z collector
oc adm policy add-cluster-role-to-user collect-audit-logs -z collector
oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z collector

oc adm policy add-cluster-role-to-user cluster-logging-write-application-logs -z collector
oc adm policy add-cluster-role-to-user cluster-logging-write-audit-logs -z collector
oc adm policy add-cluster-role-to-user cluster-logging-write-infrastructure-logs -z collector

echo " ==== UI-Plugin Logging Configuration ===== "
oc apply -f ui_plugin.yaml

echo " ======= ClusterLogForwarder Config ========= "
if [ "$DATA_MODEL" == "otel" ]; then
    oc apply -f otel_cluster_log_forwarder.yaml
else
    oc apply -f viaq_cluster_log_forwarder.yaml
fi
