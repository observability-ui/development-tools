OPERATOR_BUNDLE?=quay.io/openshift-observability-ui/observability-ui-operator-bundle:0.4.0

# Terminal output colors
GREEN?='\033[0;32m'
ENDCOLOR?='\033[0m' # No Color
RED?='\033[0;31m'

.PHONY: all
all:
	./deploy-all.sh

.PHONY: monitoring-scale-up
monitoring-scale-up:
	cd monitoring-plugin && ./scale-up.sh

.PHONY: monitoring-scale-down
monitoring-scale-down:
	cd monitoring-plugin && ./scale-down.sh

.PHONY: monitoring-cleanup
monitoring-cleanup:
	oc patch clusterversion version --type json -p "$(cat enable-monitoring.yaml)"

.PHONY: test-user
test-user:
	cd test-user-manifest && ./create-htpsswd-test-user.sh

.PHONY: dashboards
dashboards:
	(cd dashboards-manifests && ./deploy-dashboards.sh)
	(cd coo && oc apply -f ui-plugin-dashboards.yaml)

.PHONY: korrel8r
korrel8r:
	printf "\n${GREEN} *** Deploying Logging, Network Observability *** ${ENDCOLOR}\n"
	(cd  korrel8r-manifests && cd openshift && make operators && make resources)
	(cd  coo && oc apply -f ui-plugin-logging.yaml)

.PHONY: troubleshooting
troubleshooting:
	printf "\n${GREEN} *** Deploying Troubleshooting *** ${ENDCOLOR}\n"
	(cd coo && oc apply -f ui-plugin-troubleshooting.yaml)

.PHONY: tracing
tracing:
	printf "\n${GREEN} *** Deploying Tracing *** ${ENDCOLOR}\n"
	(cd  tracing-manifests && make operators && make resources)
	(cd  coo && oc apply -f ui-plugin-tracing.yaml )

.PHONY: acm
acm:
	printf "\n${GREEN} *** Deploying ACM *** ${ENDCOLOR}\n"
	(cd  acm && make operators && make resources)

.PHONY: OBO
OBO:
	operator-sdk run bundle \
	${OPERATOR_BUNDLE} \
	--install-mode AllNamespaces \
	--namespace openshift-operators \
	--security-context-config restricted
