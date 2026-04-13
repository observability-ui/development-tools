# master.sh — Demo Orchestration

End-to-end provisioning of a **Cluster Observability Operator (COO)** demo environment
with logging, tracing, htpasswd test users, Perses RBAC, global datasources and sample
dashboards.

## Prerequisites

- `oc` CLI authenticated as **cluster-admin** (e.g. `kubeadmin`).
- `htpasswd` available on `PATH`.
- Not a ROSA cluster (htpasswd identity provider is not supported on ROSA).

## Execution Steps

`master.sh` runs the following scripts in order. Each step blocks until the
previous one completes.

### 1. `z_coo.sh` — Cluster Observability Operator

Installs COO from OperatorHub (`redhat-operators`), creates the
`openshift-cluster-observability-operator` namespace, and optionally applies a
Monitoring UIPlugin and PersesGlobalDatasource TLS secrets.

Uninstall: `z_coo_uninstall.sh`

### 2. `z_logging.sh` — Logging Stack

Deploys MinIO (object storage), a chat workload, the Cluster Logging and Loki
operators, a LokiStack instance, RBAC, a ClusterLogForwarder, and a Logging
UIPlugin.

Uninstall: `z_logging_uninstall.sh`

### 3. `z_tracing.sh` — Distributed Tracing Stack

Installs the Tempo and OpenTelemetry operators, MinIO, a TempoStack, OTEL
collectors, sample applications, and a distributed-tracing UIPlugin.

Uninstall: `z_tracing_uninstall.sh`

### 4. `replace-htpssd-test-user.sh` — htpasswd Test Users

Creates six htpasswd users (`user1`–`user6`, all with password **`password`**),
stores them in an `htpass-secret` in `openshift-config`, and configures the
OAuth identity provider.

`master.sh` feeds the script non-interactively:

- **Not a ROSA cluster?** → `n`
- **Namespace for base permissions** → `openshift-monitoring`

Namespace-level roles granted in `openshift-monitoring`:

| User | Role |
|-------|------|
| user1 | `view` |
| user2 | `view` |
| user3 | `view` |
| user4 | `view` |
| user5 | `admin` |
| user6 | *(none — used to validate the UI with zero permissions)* |

### 5. `rbac_perses_e2e_user1_to_user6.sh` — Perses RBAC

Creates test namespaces and applies fine-grained Perses RBAC for each user.

#### Namespaces created

| Namespace | Purpose |
|-----------|---------|
| `perses-dev` | User-scoped dashboard/datasource namespace |
| `observ-test` | User-scoped dashboard/datasource namespace |
| `empty-namespace3` | Namespace with no pre-existing dashboards |
| `empty-namespace4` | Namespace with no pre-existing dashboards |
| `openshift-cluster-observability-operator` | Labeled `openshift.io/cluster-monitoring: "true"` |

#### ClusterRoles

| ClusterRole | Permissions |
|-------------|-------------|
| `user-reader` | Broad read-only access to cluster resources (nodes, pods, operators, CRDs, OBO/COO monitoring.rhobs resources, etc.) |
| `perses-prometheus-api-editor` | `get`, `list`, `watch`, `create`, `update` on `prometheuses/api` (`monitoring.coreos.com`) |

#### Cluster-wide bindings (all users)

Every user (`user1`–`user6`) receives:

| ClusterRoleBinding | ClusterRole |
|--------------------|-------------|
| `userN-perses-prometheus-api-editor` | `perses-prometheus-api-editor` |
| `userN-persesglobaldatasource-viewer` | `persesglobaldatasource-viewer-role` |

#### Per-user Perses RoleBindings

##### user1 — Dashboard editor + datasource editor (COO namespace) with viewer access elsewhere

| RoleBinding | Namespace | ClusterRole |
|-------------|-----------|-------------|
| `user1-editor-dashboard` | `openshift-cluster-observability-operator` | `persesdashboard-editor-role` |
| `user1-viewer-dashboard-observ-test` | `observ-test` | `persesdashboard-viewer-role` |
| `user1-editor-datasource` | `openshift-cluster-observability-operator` | `persesdatasource-editor-role` |
| `user1-viewer-datasource` | `observ-test` | `persesdatasource-viewer-role` |

##### user2 — Dashboard viewer + datasource viewer (perses-dev only)

| RoleBinding | Namespace | ClusterRole |
|-------------|-----------|-------------|
| `user2-viewer-dashboard` | `perses-dev` | `persesdashboard-viewer-role` |
| `user2-viewer-datasource` | `perses-dev` | `persesdatasource-viewer-role` |

##### user3 — Dashboard editor + datasource editor (empty-namespace3 only)

| RoleBinding | Namespace | ClusterRole |
|-------------|-----------|-------------|
| `user3-editor-dashboard` | `empty-namespace3` | `persesdashboard-editor-role` |
| `user3-editor-datasource` | `empty-namespace3` | `persesdatasource-editor-role` |

##### user4 — Dashboard viewer + datasource viewer (empty-namespace4 only)

| RoleBinding | Namespace | ClusterRole |
|-------------|-----------|-------------|
| `user4-viewer-dashboard` | `empty-namespace4` | `persesdashboard-viewer-role` |
| `user4-viewer-datasource` | `empty-namespace4` | `persesdatasource-viewer-role` |

##### user5 — No Perses namespace-level RoleBindings

Has only the cluster-wide bindings shared by all users (`perses-prometheus-api-editor` and `persesglobaldatasource-viewer-role`). Combined with `admin` on `openshift-monitoring` (step 4), user5 can manage resources there but has no Perses dashboard/datasource roles in any namespace.

##### user6 — No Perses namespace-level RoleBindings, no base namespace permissions

Has only the cluster-wide bindings shared by all users. Receives **no** namespace role from step 4 either. Used to validate that the list page shows no project dropdown and the create button is disabled.

### 6. `z_tempo_loki_thanos_persesglobaldatasource.sh` — Global Datasources

Applies three `PersesGlobalDatasource` CRs:

| Name | Plugin Kind | Target |
|------|-------------|--------|
| `thanos-querier-datasource` | `PrometheusDatasource` | `thanos-querier.openshift-monitoring.svc.cluster.local:9091` |
| `loki-datasource` | `LokiDatasource` | `logging-loki-gateway-http.openshift-logging.svc.cluster.local:8080` (application tenant) |
| `tempo-platform` | `TempoDatasource` | `tempo-platform-gateway.openshift-tracing.svc.cluster.local:8080` (platform tenant) |

### 7. `dashboards.sh` — Sample Dashboards

Interactive — prompts for a target namespace, then applies a set of sample
`PersesDashboard` and `PersesDatasource` YAML files into that namespace.

The `namespace` field in each manifest is rewritten from its default to the
namespace you provide at the prompt.

#### PersesDashboard resources

| File | CR name | Display name | Default namespace |
|------|---------|--------------|-------------------|
| `openshift-cluster-sample-dashboard.yaml` | `openshift-cluster-sample-dashboard` | Kubernetes / Compute Resources / Cluster | `openshift-cluster-observability-operator` |
| `perses-dashboard-sample.yaml` | `perses-dashboard-sample` | Perses Dashboard Sample | `perses-dev` |
| `prometheus-overview-variables.yaml` | `prometheus-overview` | Prometheus / Overview | `perses-dev` |
| `thanos-compact-overview-1var.yaml` | `thanos-compact-overview` | Thanos / Compact / Overview | `perses-dev` |
| `lmd6v93sz-acm-dashboard.yaml` | `lmd6v93sz` | Service Level dashboards / Virtual Machines by Time in Status | `openshift-cluster-observability-operator` |
| `nodeexporterfull-cr-v1alpha2.yaml` | `nodeexporterfull` | Node Exporter Full | `perses-dev` |

#### PersesDatasource resources

| File | CR name | Display name | Default namespace |
|------|---------|--------------|-------------------|
| `thanos-querier-datasource.yaml` | `thanos-querier-datasource` | Thanos Querier Datasource | `perses-dev` |

## Directory Layout

```
demo/
├── master.sh                                       # this orchestrator
├── z_coo.sh / z_coo_uninstall.sh                   # COO install / uninstall
├── z_logging.sh / z_logging_uninstall.sh            # Logging stack install / uninstall
├── z_tracing.sh / z_tracing_uninstall.sh            # Tracing stack install / uninstall
├── z_tempo_loki_thanos_persesglobaldatasource.sh    # Global datasources
└── ../rbac/
    ├── replace-htpssd-test-user.sh                  # htpasswd user provisioning
    └── coo140/
        ├── rbac_perses_e2e_user1_to_user6.sh        # Perses RBAC (this doc, step 5)
        └── dashboards/
            └── dashboards.sh                        # Sample dashboard applicator
```
