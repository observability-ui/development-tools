## Outline
- Perses intro
	- Howdy y'all, today I'll be showing off the Customizable dashboards feature our Observability UI team has been working on. It's based on the CNCF sandbox project Perses, which contains a standalone UI as well as the ability to embed portions of the UI into your own user interfaces, with modules as small as a single panel up to the entire customizable dashboard experience
	- Our usage of the perses operator enables using Kubernetes Custom Resources for gitops flows for Dashboards, Datasources and permissions and more 
- Lets jump right into create a dashboard from scratch
	- Variety of available charts available to create dashboards
	- lets start with adding a time series chart from prometheus
	- One of the things our team is most excited for is being able to use multiple datasources on a single dashboard
	- tempo - trace table
	- logs - logs table
	- Discuss GlobalDatasources vs Datasources, fallback mechanism with defaults
	- Perses uses a plugin system, so new datasources and charts are able to be added all the time. So if your team needs to show off data from a new source its simple to create a plugin for your own internal use or to contribute to upstream

```default queries
Tempo:
{}
Logs:
{ log_type="application" } | json
Prometheus:
sum(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate{namespace="openshift-monitoring"}) by (pod)
```

- One of the most common initial use cases will be importing a grafana dashboard
	- `Openshift Networking-1773356790588.json`
- Duplicate/Delete dashboard
- RBAC for users - talking about how it uses k8s rbac based on namespace permissions for perses CRD's
	- Most of the demo as kubeadmin
	- user5
		- Access to openshift-monitoring
