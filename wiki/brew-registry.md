## Getting Access to brew.registry.redhat.io
This is a private Red Hat registry. Only authorized Red Hat users will be able to access this image brew.registry.redhat.io/rh-osbs/openshift-golang-builder:rhel_8_golang_1.23 used in the Dockerfile.perses-operator.

Replace <INSERT-USERNAME> with your red hat username. 

```
kinit <INSERT-USERNAME>@IPA.REDHAT.COM
curl --negotiate -k --verbose -u <INSERT-USERNAME> : -X POST -H 'Content-Type: application/json' --data '{"description":"openshift 4 testing"}' https://employee-token-manager.registry.redhat.com/v1/tokens -s | jq 
```

Login to the registry and Copy/Paste username and password from the curl command above when prompted. 
```
podman login brew.registry.redhat.io
```

Reference Doc: https://source.redhat.com/groups/public/teamnado/wiki/brew_registry

