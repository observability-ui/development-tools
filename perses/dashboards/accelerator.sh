#!/bin/bash

#git clone git@github.com:yevgeny-shnaidman/kernel-module-management.git
#cd kernel-module-management
#git checkout yevgeny/test-perses-dashboard

make deploy IMG=quay.io/yshnaidm/kmmo:simulate-metrics KUBECONFIG=<path of kubeconfig from your cluster>