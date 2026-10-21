#!/bin/bash
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

ask_yes_no() {
    while true; do
        read -r -p "$1 [y/n]: " answer
        case "$answer" in
            y|n) return ;;
            *) echo 'Please enter y or n.' ;;
        esac
    done
}

echo 'Logging setup for a fresh disposable cluster. Existing configuration may be overwritten.'
ask_yes_no 'Install Loki and Logging operators automatically?'
install_operators=$answer

if [[ "$install_operators" == n ]]; then
    echo 'Install Loki and Logging operators manually, or use existing ready operators.'
    read -r -p 'Press Enter once both operators are ready to continue: '
fi

while true; do
    echo 'Which data model do you want to configure?'
    read -r -p 'a) OpenTelemetry  b) ViaQ: ' choice
    case "$choice" in
        a) data_model=otel; break ;;
        b) data_model=viaq; break ;;
        *) echo 'Please enter a or b.' ;;
    esac
done

# An explicit environment setting skips this question.
if [[ -z ${DEPLOY_UI_PLUGIN:-} ]]; then
    ask_yes_no 'Deploy the cluster logging UIPlugin (requires COO; not needed for the local UI)?'
    if [[ "$answer" == y ]]; then
        export DEPLOY_UI_PLUGIN=true
    else
        export DEPLOY_UI_PLUGIN=false
    fi
fi

ask_yes_no 'Deploy the searchable merged-logging-test log generator?'
deploy_test_logs=$answer

if [[ "$install_operators" == y ]]; then
    ./install-logging-operators.sh
fi
./deploy.sh "$data_model"

if [[ "$deploy_test_logs" == y ]]; then
    oc apply -f random-logs-generator-deployment.yaml
    oc rollout status deployment/log-generator -n merged-logging-test --timeout=5m
fi
