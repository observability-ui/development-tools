bundle := env("OPERATOR_BUNDLE", "quay.io/openshift-observability-ui/observability-ui-operator-bundle:0.4.0")

# # Terminal output colors
GREEN := '\033[0;32m'
ENDCOLOR := '\033[0m' # No Color
RED := '\033[0;31m'

all:
	./deploy-all.sh

scale-monitoring up_down:
	cd monitoring-plugin && ./scale.sh {{ up_down }}

monitoring-cleanup:
	oc patch clusterversion version --type json -p "$(cat enable-monitoring.yaml)"

test-user:
	cd test-user-manifest && ./create-htpsswd-test-user.sh

dashboards:
	(cd dashboards-manifests && ./deploy-dashboards.sh)
	(cd coo && oc apply -f ui-plugin-dashboards.yaml)

korrel8r:
	printf "\n${GREEN} *** Deploying Logging, Network Observability *** ${ENDCOLOR}\n"
	(cd  korrel8r-manifests && cd openshift && make operators && make resources)
	(cd  coo && oc apply -f ui-plugin-logging.yaml)

troubleshooting:
	printf "\n${GREEN} *** Deploying Troubleshooting *** ${ENDCOLOR}\n"
	(cd coo && oc apply -f ui-plugin-troubleshooting.yaml)

tracing:
	printf "\n${GREEN} *** Deploying Tracing *** ${ENDCOLOR}\n"
	(cd  tracing-manifests && make operators && make resources)
	(cd  coo && oc apply -f ui-plugin-tracing.yaml )

acm:
	printf "\n${GREEN} *** Deploying ACM Observability *** ${ENDCOLOR}\n"
	(kubectl apply -k acm/)

OBO:
	operator-sdk run bundle \
	${bundle} \
	--install-mode AllNamespaces \
	--namespace openshift-operators \
	--security-context-config restricted

build-colorize:
    bun build --minify --sourcemap ./colorize/cli.ts --compile --outfile ./colorize/bin/colorize-linux-gnu --target=bun-linux-x64
    bun build --minify --sourcemap ./colorize/cli.ts --compile --outfile ./colorize/bin/colorize-darwin --target=bun-darwin-x64
