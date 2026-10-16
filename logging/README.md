## Test merged logging in monitoring-console-plugin

On a disposable **OCP 5.1+** cluster, logged in as cluster admin, set up the
stack (or run `just logging-stack` from the repo root):

```bash
cd logging
./setup-logging-stack.sh       # Loki + Logging operators, MinIO, LokiStack, collection, test logs
```

The merged-logging UI is not deployed on the cluster: run it locally from the
monitoring-plugin checkout with `make start-mcp-console` and use
the local Console it serves.

Requirements: `oc`, the Red Hat operator catalog, access to the image
registries, and a StorageClass for Loki. `STORAGE_CLASS` defaults to the
cluster's single default StorageClass; the shipped LokiStack manifest assumes
`gp3-csi` on AWS, and the MinIO PVC always uses the cluster default.

`setup-logging-stack.sh` installs Red Hat Loki and Logging on `stable-6.5`
(`LOGGING_CHANNEL`) without the Console's mandatory AWS Role ARN field (MinIO
uses static credentials, not AWS STS), reuses the test MinIO/LokiStack
manifests, forwards application/infrastructure logs and starts a tiny
application emitting `merged-logging-test` messages.

In the local Console open **Observe > Logs**, select **Application**,
**ViaQ**, and namespace **merged-logging-test**, then search for
`merged-logging-test`. Allow time for collection. Start with an admin
account; restricted-user tests need separately provisioned log-view and
namespace permissions. Audit collection and streaming configuration are not
included.

### Safety and retry

These are fresh-cluster setups, not migration tools. The stack setup refuses
existing MinIO namespaces, LokiStacks or forwarders it did not create; stack
resources are labeled
`development-tools.observability/merged-logging-test`, so rerunning after a
partial failure is safe and skips the already-installed operators. Existing
operator Subscriptions are allowed if their channels match. **Do not run this
on the already manually configured cluster.**

There is no restore mode: teardown of a disposable cluster is deleting it.
Loki, MinIO, the test workload and collection remain either way.

The test MinIO uses `quay.io/minio/aistor/minio`, MinIO's publicly pullable
publish of the same server under the AIStor project, because the classic
`quay.io/minio/minio` repo is access-restricted (pulls return unauthorized
even with a valid quay login). The image has no shell, so an initContainer
pre-creates the `loki` bucket. It has
fixed, public test credentials and static storage. Do not expose MinIO or use
this storage configuration in production. A single 4-CPU/16-GB node may be
tight for the full stack.

Offline check:

```bash
bash -n logging/setup-logging-stack.sh
```

## Install standalone logging-view-plugin and LokiStack

1. Create an OCP cluster. Navigate to the console UI. 
2. Manually Install from the OperatorHub 
    - [ ] Red Hat OpenShift Logging Operator, 
    - [ ] Loki Operator, 
    - [ ] Cluster Observability Operator (COO)
3. `oc login ...`
4. Run the script "start.sh" to deploy minio storage, lokistack, and clusterLogForwarder (either Otel or ViaQ), you'll be prompted which data model you want to use
```
$ cd components 
$ ./start.sh

Which data model do you want to configure?
a) otel b) viaQ
Enter your choice (a or b): b
 ** Data Model used wil be : viaq ** 
 ========================================== 
 ========= Minio Configuration ============ 
namespace/minio created
secret/minio created
service/minio created
deployment.apps/minio created
persistentvolumeclaim/minio created
 ========= LokiStack Configuration ======== 
Warning: resource namespaces/openshift-logging is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by oc apply. oc apply should only be used on resources created declaratively by either oc create --save-config or oc apply. The missing annotation will be patched automatically.
namespace/openshift-logging configured
secret/minio created
lokistack.loki.grafana.com/logging-loki created
 ======= Collector Configurguration ======= 
Already on project "openshift-logging" on server "https://api.sno-4xlarge-418-s82xk.dev07.red-chesterfield.com:6443".
serviceaccount/collector created
clusterrole.rbac.authorization.k8s.io/logging-collector-logs-writer added: "collector"
clusterrole.rbac.authorization.k8s.io/collect-application-logs added: "collector"
clusterrole.rbac.authorization.k8s.io/collect-audit-logs added: "collector"
clusterrole.rbac.authorization.k8s.io/collect-infrastructure-logs added: "collector"
 ==== UI-Plugin Logging Configuration ===== 
uiplugin.observability.openshift.io/logging created
 ======= ClusterLogForwarder Config ========= 
clusterlogforwarder.observability.openshift.io/collector created
(base) 
```
