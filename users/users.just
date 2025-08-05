add-htpasswd-user username password:
    htpasswd -b "{{source_directory()}}/users.htpasswd" {{ username }} {{ password }}

create-users-secret up_down:
    if [ "{{ up_down }}" == "up" ]; then oc get secret htpass-secret -n openshift-config >/dev/null 2>&1 && echo "Secret already exists, skipping creation" && exit 0; oc create secret generic htpass-secret --from-file=htpasswd="{{source_directory()}}/users.htpasswd" -n openshift-config; fi
    if [ "{{ up_down }}" == "down" ]; then oc delete secret htpass-secret -n openshift-config; fi

create-users-auth up_down:
    if [ "{{ up_down }}" == "up" ]; then oc apply -f "{{source_directory()}}/oauth.yaml"; fi
    if [ "{{ up_down }}" == "down" ]; then oc delete -f "{{source_directory()}}/oauth.yaml"; fi

add-view-permissions up_down namespace user:
    "{{source_directory()}}/give-view-permissions.sh" {{ up_down }} {{ namespace }} {{ user }}

deploy-users up_down: (create-users-secret up_down) (create-users-auth up_down) (add-view-permissions up_down "openshift-monitoring" "user")
