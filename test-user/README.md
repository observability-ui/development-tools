# Create a htpasswd test user 

### To create a htpasswd, run the script: 
```
./create-htpsswd-test-user.sh
```

### Purpose 
- Create a test user not a cluster administration
- User has restricted access to namespaces 
- User has limited abilities (e.g. view-only permissions)

### Resources 
Scripts are based off of openshift docs : https://docs.openshift.com/container-platform/4.16/authentication/identity_providers/configuring-htpasswd-identity-provider.html

### Expected Results 

![Login screen after test user has been created](image-1.png)

<b> Figure 1. </b> Login screen after test user has been created. If you are using the OpenShift user interface > Click 'my_htpwassd_provider' and login with the username: test-user and password: password.  