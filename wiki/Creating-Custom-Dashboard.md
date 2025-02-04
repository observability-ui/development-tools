# Create a Dashboard
Create a new yaml file named *dashboard.yaml*
```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  labels:
    console.openshift.io/dashboard: 'true'
    console.openshift.io/odc-dashboard: 'true'
  name: world-dashboard
  namespace: openshift-config-managed
data:
  etcd.json: |-
    {
      "description": "Test Dashboard",
      "editable": true,
      "gnetId": null,
      "hideControls": false,
      "refresh": "10s",
      "panels": [
        {
          "legend": {
            "show": true
          },
          "stack": true,
          "targets": [
            {
              "expr": "instance:apiserver_request_total:rate5m"
            }
          ],
          "title": "API Total Request Count",
          "type": "graph"
        }
      ]
    }
```

Then Apply it.

```sh
oc apply -f dashboard.yaml`

 This new dashboard should show up under **Administrator > Observe > Dashboards** and **Developer > Observe > Dashboard**.
