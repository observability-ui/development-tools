# Hub Cluster
Primary Reference: [[ACM MOC]]
 
---

The hub cluster is a central controller of [[ACM]]. It contains a console similar to [[OCP]], the [[ACM]] API, and other product components. You can enable Observability on the cluster to view monitor metrics from the other managed clusters.

It uses the `MultiClusterHub` (MCH) to manage, update and install hub cluster components. It aggregate info using a asynchronous work-request model and search collectors.

If a hub cluster is also a [[Managed Cluster]] then it is referred to as a local cluster.

## Control Mechanisms
### Cluster Lifecycle
The *cluster lifecycle* refers to the creation, importing, exporting, managing, and deleting of Kubernetes clusters across various infra clouds, private clouds, and on prem data centers.

The [[Hive]] controller is the application which provisions the clusters.

The [[Managed Cluster Import Controller]] is used to deploy [[klusterlet]] onto the [[Managed Cluster]].

The [[Klusterlet Add-on Controller]] is used to deploy add-ons.

### Application Lifecycle
Control and deploy applications across clusters. Use Ansible Tower jobs to automate these tasks.

### Governance
Define policies which enforce security compliance or notify you of changes which violate compliance requirements

### Observability
Connects to 4.x OCP [[Managed Cluster]] to retrieve alerts. Uses Multi-Cluster Observability Operate (MCO) to monitor the managed clusters.

