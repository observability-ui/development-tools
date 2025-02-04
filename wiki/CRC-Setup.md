This is a set of notes and steps to complete the next steps document.

## Install Dependencies
### CRC
Go [here](https://crc.dev/docs/installing/) to download CRC.

### OC
```
homebrew install openshift-cli
```

## Configuration
### Create a CRC Instance
Run the following commands
```zsh
crc config set enable-cluster-monitoring true
crc config set memory 23840
crc config set cpus 8
crc config set disk-size 150
```

> [!INFO]
> These are suggested values for running monitoring and other applications on your cluster. If you have more pressing needs you will need to add more, or move to a full cluster

```zsh
crc setup
# crc daemon # this is only required on old versions of crc
crc start
crc login https://api.crc.testing:6443 -u kubeadmin -p {PasswordHere}
```
### Enable User Application Monitoring
Create the following yaml file as `cluster-monitoring-config.yaml`
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
```

Run the following command to instantiate the object
```fsh
oc apply -f cluster-monitoring-config.yaml
```
