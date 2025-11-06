# QE process for COO release testing (Monitoring UIPlugin and Integrated testing)
Reference:<br>
[Cluster Observability Operator Acceptance Test](https://docs.google.com/document/d/1rBio1lFD3GzWqVP35ZLUdfVDNPwjDSxG08wy5Yo2tG8/edit?usp=sharing) GDrive doc

Note: It is written in my own words and a bit of lack of knowledge in terms of concepts. It is just to give a quick overview and steps to follow in order to perform COO release testing by anyone in the team.

## Installation
Usually, COO release testing phase starts right after the COO RC (feature freeze), when FBC files starts to be provided by [Hongyan Li - @hongyli](https://redhat.enterprise.slack.com/archives/D08E0L91YHF) in [#coo-productization channel](https://redhat.enterprise.slack.com/archives/C063J3F88MV).

When it is stable enough, Stage files starts to be provided as well. In a practical way, the difference between them are IDMS (Image Digest Mirror Set) where images are mirrored to other registries than the official one.

### Bundle
This is an example of a bundle:

> quay.io/redhat-user-workloads/cluster-observabilit-tenant/cluster-observability-operator/cluster-observability-operator-bundle@sha256:373e690b53cfd8e2ef3c22cf12558384f0de64577f1241dc12d598559d151050

Bundle can also refer to quay registry or stage. We should also create a IDMS accordingly.

IDMS for **Quay**:

    oc apply -f - <<EOF
    apiVersion: config.openshift.io/v1
    kind: ImageDigestMirrorSet
    metadata:
     name: idms-coo
    spec:
     imageDigestMirrors:
    - mirrors:
      - quay.io/redhat-user-workloads/cluster-observabilit-tenant/cluster-observability-operator
      source: registry.redhat.io/cluster-observability-operator
    EOF

IDMS for **Stage**:

    oc apply -f - <<EOF
    apiVersion: config.openshift.io/v1
    kind: ImageDigestMirrorSet
    metadata:
     name: idms-coo
    spec:
     imageDigestMirrors:
    - mirrors:
      - registry.stage.redhat.io
      source: registry.redhat.io
    EOF

#### How to install the bundle

Run **qe-release-testing/bundle/coo_bundle.sh** and it will prompt:
- bundle
- quay or stage
- choice of ocp version as 4.12/4.18 or 4.19+

It will create:
- openshift-cluster-observability-operator namespace
- IDMS according to the option
- run the installation with/without **--security-context-config restricted** parameter depending on ocp version

#### How to uninstall the bundle

Run **qe-release-testing/bundle/cleanup_bundle.sh**

### FBC image installation

Run **qe-release-testing/fbc/coo_fbc.sh** and it will prompt:
- FBC image for your ocp cluster version

Example:
>quay.io/redhat-user-workloads/cluster-observabilit-tenant/cluster-observability-operator/coo-fbc-**v4-18**@sha256:5b7c9c99daac7a01798a146c631d7e464b9cfb29ed30bfb2e4ca1e2dfad93f25

Notice that for each ocp version we have a FBC image.

### Stage image installation

Run **qe-release-testing/fbc/coo_stage.sh** and it will prompt:
- Stage image for your ocp cluster version

Note: For Stage images, they are generated in Konflux, as an example:

>**registry-proxy.engineering.redhat.com**/rh-osbs/iib@sha256:f36d9c545eeaa5b5dcd8139f2d0a914672ff76387734c05d30c85558d823e721

We need to replace from **registry-proxy.engineering.redhat.com** to **brew.registry.redhat.io**, ending
>**brew.registry.redhat.io**/rh-osbs/iib@sha256:f36d9c545eeaa5b5dcd8139f2d0a914672ff76387734c05d30c85558d823e721

## Monitoring UIPlugin
References: <br>
- [Observability UIPlugin](https://github.com/rhobs/observability-operator/blob/main/docs/user-guides/observability-ui-plugins.md)<br>
- [UIPlugins official doc](https://docs.redhat.com/en/documentation/red_hat_openshift_cluster_observability_operator/1-latest/html-single/ui_plugins_for_red_hat_openshift_cluster_observability_operator/index#observability-ui-plugins-overview)

Definition:
```
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: monitoring
spec:
  type: Monitoring
  monitoring:
    acm:
      enabled: true
      alertmanager:
        url: 'https://alertmanager.open-cluster-management-observability.svc:9095'
      thanosQuerier:
        url: 'https://rbac-query-proxy.open-cluster-management-observability.svc:8443'
    perses:
      enabled: true
    incidents:
      enabled: true
```

### Installation of Monitoring UIPlugin:
Run **qe-release-testing/uiplugins/monitoring.sh**

It contains ACM, Incidents and Perses feature flags. If you don't want a certain feature:
- you can edit the YAML in this shell script
- install it and go to COO and edit Monitoring UIPlugin YAML by turning to false the feature or remove it from the YAML

### Standalone testing
By saying Standalone testing, it means Monitoring UIPlugin can be tested without any other operator/product installed in OCP cluster. <br>
Incidents and Perses features are enabled only with the installation of Monitoring UIPlugin when these features are enabled.

#### Incidents
Reference: <br>
[Incident Detection TP - Technical Enablement](https://docs.google.com/presentation/d/1YsgHaB1ShVSH14lla9a3HJ5Eqd5A5vBm25NtjUaMIsE/edit?usp=sharing)<br>

A difference between **COO installed from OperatorHub** (meaning a released version) and **development version** is that, when installing from OperatorHub, all resources are created: namespace, catalogSource, operatorGroup, Subscription and when you are installing Bundle, FBC or Stage image you need to create some or all.

- COO installed from OperatorHub<br>
**openshift-cluster-observability-operator** namespace when created by COO installed from OperatorHub does not contain the label **openshift.io/cluster-monitoring: "true"**, that impacts Incidents functionality. You need to manually add it:

1. Go to Administration > Namespaces
2. Search for openshift-cluster-observability-operator
3. Switch to YAML tab
4. Verify if this label exist: **openshift.io/cluster-monitoring: 'true'**
5. If not, include it
6. Save and Reload
7. Go To Workloads > Deployments
8. Search for health-analyzer
9. Click on kebab icon > Restart rollout
10. Then go back to Observe > Targets and verify **health-analyzer** ServiceMonitor is listed with metrics endpoint
11. Wait a bit and you will see alerts/incidents in graphs under Observe > Alerting > Incidents tab.

- COO installed via Bundle, FBC or Stage images<br>
You don't need to do anything, once label will already be added via namespace shell script creation, as well as other resources like operatorGroup, catalogSource, IDMS, Subscription.

#### Perses
Refereces:<br>
- [COO1.2.1 - Perses RBAC feature](https://docs.google.com/document/d/16Oq3PmYJN8Nv2ejmvetAOKOy6pZ7Icnwtld2HsVLl0o/edit?usp=sharing)
- [Monitoring UIPlugin - Perses RBAC](https://github.com/rhobs/observability-operator/blob/main/docs/user-guides/observability-ui-plugins.md#monitoring)

When installing COO, perses-operator will be deployed, independently of Monitoring UIPlugin. <br>
After Monitoring UIPlugin installation, perses-0 pod will be created and it will enable:
    - Observe > Dashboards (Perses)
    - Accelerators dashboard will be created OOTB (out of the box starting COO1.2.1)
    - APM dashboard will also be created OOTB (out of the box starting COO1.3.0)

##### Perses Dashboards and Perses Datasources
In COO, you will see Perses Dashboards and Perses Datasources tabs with Accelerators and APM dashboards, as well as Accelerators thanos-queries datasource.

The ability to create, read, update, delete (CRUD) actions on Perses Dashboards and Perses Datasources are driven by RBAC. Read more about it on references above.

### Integrated testing
When other operators/products are installed in OCP cluster and COO + Monitoring UIPlugin are also installed, it enabled Observe section under different perspectives.

#### Virtualization aka Kubevirt
Fleet Management perspective will display **Observe** section containing:
- Alerting with Alerts, Silences, Alerting Rules
- Metrics
- Dashboards
- Dashboards (Perses)
- Targets

**It will not display Incidents tab**, even if Incidents feature is enabled. It is only enabled under Admninistration perspective.

To install ACM you can: 
1. run **/development-tools/virtualization/virtualization.sh**
2. wait the operator to have Succeeded status
3. run **/development-tools/virtualization/virtualization1.sh**

#### Advanced Cluster Management for Kubernetes aka ACM
Fleet Management perspective will display **Observe** section containing:
- Alerting with Alerts, Silences, Alerting Rules
- Dashboards (with Perses dashboards displayed)

**It will not display Incidents tab**, even if Incidents feature is enabled. It is only enabled under Admninistration perspective.

To install ACM you can: 
1. run **/development-tools/acm/acm.sh**
2. wait the operator to have Succeeded status
3. run **/development-tools/acm/acm1.sh**

#### Troubleshooting Panel UIPlugin
Troubleshooting Panel UIPlugin with Monitoring UIPlugin enables Troubleshooting Panel button/link on Alert Details page on Administration perspective:
1. Administration perspective > Observe > Alerting > Alerts tab
2. Click on an alert
3. Alert Details page will be displayed with Troubleshooting Panel link on top of metric graph

This Troubleshooting Panel button/link **should not be displayed** on Alert Details page under:
- Fleet Management
- Virtualization
- Developer

## Upgrade testing

### Source state
1. Install current released version from OperatorHub
2. Install all UIPlugins, in this case Monitoring UIPlugin with all feature enabled and Troubleshooting Panel UIPlugin
3. Install ACM
4. Install Virtualization
5. Perform a smoke test to verify all related features are working fine, specially Incidents shown in the graph before upgrading it

###Target state
1. Install Bundle, FBC or Stage images<br>
a. Bundle: run **bundle/coo_bundle_upgrade.sh**<br>
b. FBC: run **fbc/coo_fbc_upgrade.sh**<br>
c. Stage: run **stage/coo_stage_upgrade.sh**<br>
2. Watch current released version being replaced by new version
3. Monitoring and Troubleshooting Panel pods should be running
4. Perses-0 pod should be running
5. Health-analyzer pod should be running
6. Monitoring UIPlugin YAML content should be displayed successfully
7. Under COO > ObservabilityInstaller tab should be displayed (in COO1.3.0)
8. Incidents tab should be displayed successfully with alerts/incidents in the graph<br>
8.1 from COO1.2.2 to COO1.3.0 it should be moved from Observe > Incidents page to Observe > Alerting > Incidents tab
9. Troubleshooting Panel UI should be changed (from COO1.2.2 to COO1.3.0)
10. Perses APM dashboard should be created (from COO1.2.2 to COO1.3.0)
11. Under COO > ObservabilityInstaller tab should be displayed (in COO1.3.0)