
This directory was taken copied from this repo: https://github.com/korrel8r/korrel8r/tree/main/hack

# Log-in to a cluster

Log into an existing OpenShift cluster as `kubeadmin` or other user with the `cluster-admin` role.

To create a test cluster on your own machine install
https://developers.redhat.com/products/openshift-local/overview[OpenShift Local]

# Installing Operators

To install operators from the command line:

```
make operators
```

Deploys the following:

- Loki Operator in namespace `openshift-operators-redhat`
- Red Hat OpenShift Logging Operator in namespace `openshift-logging`
- Network Observability Operator in namespace `openshift-netobserv-operator`

NOTES: Alternatively you can  install the operators in the Openshift console from _Operators > OperatorHub_.
Use the "Provided by Red Hat" version of each operator.


# Creating resources

Create an instance of the required resources for each operator, from the CLI:

```
make resources
```

Deploys into the following namespaces:

- `minio`: deploys minio to provide local S3 storage.
- `openshift-logging`: `cluserlogging` and `clusterlogforwarder` with `lokistack` for log storage.
- `netobserv`: `flowcollector` with  `lokistack` for flow event storage.

# Viewing in the Console

From the OpenShift console:

- _Observe > Logs_
- _Observe > Network Traffic_

# Uninstalling

```
make clean-resources
make clean-operators
```
