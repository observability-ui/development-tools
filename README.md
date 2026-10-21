# development-tools
A centralized location for the openshift observability-ui team to keep development-related scripts and information.

## Merged logging test setup

To set up a fresh development cluster with Loki, collection and test logs, run
`just logging-stack`, or follow the scripts in the logging setup guide. The merged-logging UI
is not deployed on the cluster: run it locally from the monitoring-plugin
checkout with `make start-mcp-console`.
See [logging setup](logging/README.md#test-merged-logging-in-monitoring-console-plugin)
for prerequisites, overrides and limitations.

## Development
This repo uses a [Justfile](https://github.com/casey/just) to maintain it's commands. To pass your own image of the observability operator bundle set the environment variable `OPERATOR_BUNDLE`. For example:

```bash
OPERATOR_BUNDLE="quay.io/test/observability-operator-bundle" just OBO
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
