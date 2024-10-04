all: operators resources

operators:
	# acm and mco are too big for a standard clusterbot cluster, so scheduling on the master nodes is required
	kubectl patch Scheduler cluster --type='json' -p '[{ "op": "replace", "path": "/spec/mastersSchedulable", "value": true }]'
	kubectl apply -k config/operators
	../wait.sh subscription open-cluster-management advanced-cluster-management

# honestly way too many deployments to wait for them all. As long as one comes up
# just accept it and move on
ACM_ROLLOUT=../wait.sh rollout open-cluster-management \
deployment.apps/multiclusterhub-operator

# Same here, but we have 3 things to care about
# 1. minio deployment since thats what the storage relies on
# 2. thanos-querier
# 3. alertmanager
MCO_ROLLOUT=../wait.sh rollout open-cluster-management-observability \
statefulset.apps/observability-alertmanager \
deployment.apps/observability-rbac-query-proxy

resources: $(STORAGE_ENV)
	kubectl apply -k config/resources
	$(ACM_ROLLOUT)
	$(MCO_ROLLOUT)

clean-operators:
	kubectl delete --ignore-not-found -k config/operators

clean-resources:
	kubectl delete --ignore-not-found -k config/resources

clean-all: clean-resources clean-operators
