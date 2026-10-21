## Test merged logging in monitoring-console-plugin

Use a fresh, disposable cluster, logged in as cluster admin. Requirements:
`oc`, Bash, access to the Red Hat operator catalog and image registries, and a
default StorageClass for MinIO. The catalog must offer the selected Logging
and Loki operator channel.

Run `just logging-stack` from the repo root, or
`./logging/components/start.sh`. It asks whether to install the operators
automatically or let you install them manually, which data model to use,
whether to deploy the cluster UIPlugin, and whether to start the test log
generator. For local merged-logging testing, choose **ViaQ**, **no UIPlugin**,
and **yes to test logs**. The manual operator path pauses until you confirm
that both operators are ready.

For non-interactive setup, run the steps separately:

```bash
# Install Loki and Logging operators and wait for them to be ready.
./logging/components/install-logging-operators.sh

# Deploy storage, LokiStack and ViaQ collection without the cluster UI plugin.
DEPLOY_UI_PLUGIN=false ./logging/components/deploy.sh viaq

# Add a known, searchable message every five seconds.
oc apply -f logging/components/random-logs-generator-deployment.yaml
oc rollout status deployment/log-generator -n merged-logging-test --timeout=5m
```

If the operators are already installed and ready, skip `install-logging-operators.sh`.
It defaults to `LOGGING_CHANNEL=stable-6.5` and refuses to change the channel
of an existing subscription. It does not install COO (Cluster Observability
Operator), which is not needed for local UI testing.

`deploy.sh` uses the cluster's single default StorageClass for Loki. Set
`STORAGE_CLASS` to override it; MinIO always uses the cluster default.
Collection can use `viaq` or `otel`. Setting `DEPLOY_UI_PLUGIN=true` or
`false` also skips the UIPlugin question in `start.sh`.

Run the merged-logging UI locally from the monitoring-plugin checkout with
`make start-mcp-console`. In its Console open **Observe > Logs**, select
**Application**, **ViaQ**, and namespace **merged-logging-test**, then search
for `merged-logging-test`. Allow time for collection. Start with an admin
account; restricted-user tests need separately provisioned log-view and
namespace permissions. The shipped forwarders collect application and
infrastructure logs, not audit logs. Streaming configuration is not included.

### Safety and retry

These scripts are not migration tools. They apply shared, fixed-name
resources and can overwrite existing configuration. **Do not run them on an
already manually configured cluster.** They stop on errors; rerunning
reapplies resources and reuses existing operator subscriptions on the same
channel. There is no restore or automatic teardown mode.

MinIO uses `quay.io/minio/aistor/minio:latest` and an initContainer to create
the `loki` bucket directory. It has fixed, public test credentials and static
storage. Do not expose MinIO or use this configuration in production. A
single 4-CPU/16-GB node may be tight for the full stack.

### Standalone logging UI

Install COO separately, then run:

```bash
./logging/components/start.sh
```

Answer **yes** to the UIPlugin question to deploy the cluster logging UI.
Direct calls to `deploy.sh` still default to deploying it. Setting
`DEPLOY_UI_PLUGIN=false` skips applying that resource; it does not delete an
existing UIPlugin.

### Offline checks

```bash
for script in logging/components/{install-logging-operators,start,deploy}.sh; do
    bash -n "$script" || exit
done
```
