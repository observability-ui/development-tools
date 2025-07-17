# development-tools
A centralized location for the openshift observability-ui team to keep development-related scripts and information.

## Development
This repo uses a [Justfile](https://github.com/casey/just) to maintain it's commands. To pass your own image of the observability operator bundle use the flag `OPERATOR_BUNDLE`. For example:

```bash
just coo-resources OPERATOR_BUNDLE="quay.io/test/observability-operator-bundle"
```

The repo uses an up/down system for manipulating your cluster, for example:

```bash
just scale-monitoring down
```
Will scale down the Cluster Monitoring Operator and the monitoring-plugin.

```bash
just scale-monitoring up
```
Will scale the Cluster Monitoring Operator and the monitoring-plugin back up to their original number of replicas.

This repo uses the bash-language-server to lint and format files:
- [vscode](https://marketplace.visualstudio.com/items?itemName=mads-hartmann.bash-ide-vscode)
- [zed](https://github.com/bash-lsp/bash-language-server)
- [lsp](https://github.com/bash-lsp/bash-language-server)

This repo uses [bun](https://bun.sh/) to bundle create and bundle a fork of the shikijs/cli which is able to have command results piped into it.

## Miro Mind Map
[https://miro.com/app/board/uXjVIHGY4-A=/](https://miro.com/app/board/uXjVIHGY4-A=/)

## UI Plugins Life Cycle
https://docs.google.com/spreadsheets/d/1iJP8hjod1J_Wqv_sfGglwVYquhsHLRlqjoyvrMBv0FY/edit?gid=0#gid=0

## OCP Life Cycle
https://access.redhat.com/support/policy/updates/openshift

## Compatibility Matrix
https://github.com/rhobs/observability-operator/blob/main/docs/user-guides/observability-ui-plugins.md

| __COO Version__ |   __OCP Versions__  | __Dashboards__ | __Distributed Tracing__ | __Logging__ | __Troubleshooting Panel__ | __Monitoring__ |
| --------------- | ------------------- | -------------- | ----------------------- | ----------- | ------------------------- | ---------------|
| 0.2.0           | 4.11                |       ✔        |             ✘           |       ✘     |             ✘             |       ✘       |
| 0.3.0 - 0.4.0   | 4.11 - 4.15         |       ✔        |             ✔           |       ✔     |             ✘             |       ✘       |
| 0.3.0 - 0.4.0   | 4.16+               |       ✔        |             ✔           |       ✔     |             ✔             |       ✘       |
| 1.0.0+          | 4.11 - 4.14         |       ✔        |             ✔           |       ✔     |             ✘             |       ✘       |
| 1.0.0+          | 4.15                |       ✔        |             ✔           |       ✔     |             ✘             |       ✔       |
| 1.0.0+          | 4.16+               |       ✔        |             ✔           |       ✔     |             ✔             |       ✔       |


### Details on Monitoring Plugin Image Streams: Breaking Changes
| __COO Version__  | __OCP Versions__    | __Breaking Change__  |
| ---------------  | ------------------- | -------------------  |
|COO 1             | 4.12 - 4.14         | PF4                  |
|COO 1.1           | 4.15 - 4-18         | PF5                  |
|COO TBD           | 4.19+               | PF6                  |

Upcoming breaking change
1. React Router may land in OCP 4.19 or 4.20

Minimize breaking changes to the same version to avoid multiple streams
1. Konflux maintence of multiple versions/streams of the same component (e.g. Distributed-tracing-0.3, Distributed-tracing-0.4, Logging 6.0 Logging 6.1 all packaged in  COO 1.2)
2. Backporting becomes more complex. We cannot automatically backport; some manual adjustments are required to accommodate breaking changes.

### OpenShift Console Versions vs PatternFly Versions
https://github.com/openshift/console/blob/main/frontend/packages/console-dynamic-plugin-sdk/README.md#openshift-console-versions-vs-patternfly-versions

Each Console version supports specific version(s) of [PatternFly](https://www.patternfly.org/) in terms
of CSS styling. This table will help align compatible versions of PatternFly to versions of the OpenShift
Console.

| Console Version | PatternFly Versions | Notes                                 |
| --------------- | ------------------- | ------------------------------------- |
| 4.19.x          | 6.x + 5.x           | New dynamic plugins should use PF 6.x |
| 4.15.x - 4.18.x | 5.x + 4.x           | New dynamic plugins should use PF 5.x |
| 4.12.x - 4.14.x | 4.x                 |                                       |


## ROSA Clusters
Requires a STS role
'ManagedOpenShift'

https://docs.openshift.com/rosa/rosa_install_access_delete_clusters/rosa-sts-creating-a-cluster-quickly.html

## Konflux
1. UI [https://console.redhat.com/application-pipeline/workspaces/jezhu/applications/perses-operator-staging/activity/pipelineruns](https://console.redhat.com/application-pipeline/workspaces/cluster-observabilit/applications)


## Testing
#### Monitoring Test Plan
https://docs.google.com/document/d/1ZtGEFDOIsLDHnp8Gd0bq41RaRkm0_nrp37gj-mNo9BI/edit?usp=sharing

### COO Acceptance Criteria
https://docs.google.com/document/d/1rBio1lFD3GzWqVP35ZLUdfVDNPwjDSxG08wy5Yo2tG8/edit?tab=t.0#heading=h.bupciudrwmna
