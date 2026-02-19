# # Script is up to date as of OCP 4.16 docs : https://docs.openshift.com/container-platform/4.16/authentication/identity_providers/configuring-htpasswd-identity-provider.html

# Terminal output colors
    GREEN='\033[0;32m'
    ENDCOLOR='\033[0m' # No Color
    RED='\033[0;31m'

# Constants 
    DEFAULT_NAMESPACE="openshift-monitoring"
    USER1="user1"
    USER2="user2"
    USER3="user3"
    USER4="user4"
    USER5="user5"
    USER6="user6"
    DEFAULT_HTPASSWD_FILE="./users.htpasswd"


# Warning about ROSA 
    echo "${RED} *** WARNING: This does NOT work with ROSA cluster *** ${ENDCOLOR}\n" 

# Confirm user is not using a ROSA cluster 
    read -p "$(printf "Are you working with a ROSA cluster? (Y/N): ")" confirm && [[ $confirm == [nN] || $confirm == [nN][oO] ]] ||  exit 1

# Confirm signed in as kubeadmin (needed to grant permissions to test-user)
    ## oc whoami > if not kubeadmin > exit 

# Using default test-user 
    echo "Using default test user"
    echo "username: ${GREEN} ${USER1} ${ENDCOLOR}"
    echo "password: ${GREEN} password ${ENDCOLOR} \n"
    echo "username: ${GREEN} ${USER2} ${ENDCOLOR}"
    echo "password: ${GREEN} password ${ENDCOLOR} \n"
    echo "username: ${GREEN} ${USER3} ${ENDCOLOR}"
    echo "password: ${GREEN} password ${ENDCOLOR} \n"
    echo "username: ${GREEN} ${USER4} ${ENDCOLOR}"
    echo "password: ${GREEN} password ${ENDCOLOR} \n"
    echo "username: ${GREEN} ${USER5} ${ENDCOLOR}"
    echo "password: ${GREEN} password ${ENDCOLOR} \n"
    echo "username: ${GREEN} ${USER6} ${ENDCOLOR}"
    echo "password: ${GREEN} password ${ENDCOLOR} \n"

# To create a different htpsswd user use the following command: 
    # htpasswd -c -B -b </path/to/users.htpasswd> <username> <password>
    htpasswd -c -B -b users.htpasswd ${USER1} password
    htpasswd -B -b users.htpasswd ${USER2} password
    htpasswd -B -b users.htpasswd ${USER3} password
    htpasswd -B -b users.htpasswd ${USER4} password
    htpasswd -B -b users.htpasswd ${USER5} password
    htpasswd -B -b users.htpasswd ${USER6} password

# Create the htpsswd secret 
    echo "${GREEN} ** Creating htpsswd secret ** ${ENDCOLOR}"
    oc delete secret htpass-secret -n openshift-config
    oc create secret generic htpass-secret --from-file=htpasswd=$DEFAULT_HTPASSWD_FILE -n openshift-config 
    echo "\n"

# Define an htpasswd identity provider resource that references the secret (i.e. `./oauth-custom-resource.yaml`)
# Apply the resource to the default OAuth configuration to add the identity provider.
    echo "${GREEN}** Configuring OAuth for user ** ${ENDCOLOR} "
    oc apply -f ./oauth-custom-resource.yaml
    echo "\n"

# Sleep -- wait for test-user account to be created 
    echo " ${GREEN}** Sleeping for 60s to await ${USER1} account creation ** ${ENDCOLOR}"
    sleep 60
    echo "\n"

# Ask user what namespace they want the user to have persmissions applied on 
    echo "${GREEN}** Apply permission to user ** ${ENDCOLOR} \n"

    read -p "$(printf "${GREEN}What namespace do you want the user to have permissions on (e.g. openshift-monitoring)?  ${ENDCOLOR}" ) " namespace 

    if [[ $namespace == "" ]]; then
        NAMESPACE=$DEFAULT_NAMESPACE
        echo "\nThe default namespace will be used: ${GREEN} $DEFAULT_NAMESPACE ${ENDCOLOR} \n"
    else
        NAMESPACE=$namespace
        echo "\nThe namespace ${GREEN} $NAMESPACE ${ENDCOLOR} will be used \n"
    fi

# Apply permissions to test-user - you must be logged in a cluster administratior (e.g. kubeadmin)
    echo "\n** Granting permission for  \n user: ${GREEN} ${USER1}  ${ENDCOLOR}   \n namepsace: ${GREEN} ${NAMESPACE} ${ENDCOLOR}\n "
    
    # echo "${GREEN}Granting policy add-role-to-user view ${ENDCOLOR}  " 
    oc -n ${NAMESPACE} policy add-role-to-user view ${USER1}
    
    # echo "${GREEN}Granting policy add-role-to-user cluster-logging-application-view ${ENDCOLOR}  " 
    # oc -n ${NAMESPACE} policy add-role-to-user cluster-logging-application-view ${USER1}
    
    # echo "${GREEN}Granting policy add-role-to-user monitoring-rules-edit ${ENDCOLOR}  " 
    # oc -n ${NAMESPACE} policy add-role-to-user monitoring-rules-edit ${USER1}
    
    # echo "${GREEN}Granting policy add-role-to-user cluster-monitoring-view ${ENDCOLOR} " 
    # oc -n ${NAMESPACE} policy add-role-to-user cluster-monitoring-view  ${USER1}

# Apply permissions to test-user - you must be logged in a cluster administratior (e.g. kubeadmin)
    echo "\n** Granting permission for  \n user: ${GREEN} ${USER2}  ${ENDCOLOR}   \n namepsace: ${GREEN} ${NAMESPACE} ${ENDCOLOR}\n "
    
    # echo "${GREEN}Granting policy add-role-to-user view ${ENDCOLOR}  " 
    oc -n ${NAMESPACE} policy add-role-to-user view ${USER2}
    
    # echo "${GREEN}Granting policy add-role-to-user cluster-logging-application-view ${ENDCOLOR}  " 
    # oc -n ${NAMESPACE} policy add-role-to-user cluster-logging-application-view ${USER1}
    
    # echo "${GREEN}Granting policy add-role-to-user monitoring-rules-edit ${ENDCOLOR}  " 
    # oc -n ${NAMESPACE} policy add-role-to-user monitoring-rules-edit ${USER1}
    
    # echo "${GREEN}Granting policy add-role-to-user cluster-monitoring-view ${ENDCOLOR} " 
    # oc -n ${NAMESPACE} policy add-role-to-user cluster-monitoring-view  ${USER1}

# Apply permissions to test-user - you must be logged in a cluster administratior (e.g. kubeadmin)
    echo "\n** Granting permission for  \n user: ${GREEN} ${USER3}  ${ENDCOLOR}   \n namepsace: ${GREEN} ${NAMESPACE} ${ENDCOLOR}\n "
    
    # echo "${GREEN}Granting policy add-role-to-user view ${ENDCOLOR}  " 
    oc -n ${NAMESPACE} policy add-role-to-user view ${USER3}
    
    # echo "${GREEN}Granting policy add-role-to-user cluster-logging-application-view ${ENDCOLOR}  " 
    # oc -n ${NAMESPACE} policy add-role-to-user cluster-logging-application-view ${USER3}
    
    # echo "${GREEN}Granting policy add-role-to-user monitoring-rules-edit ${ENDCOLOR}  " 
    # oc -n ${NAMESPACE} policy add-role-to-user monitoring-rules-edit ${USER3}
    
    # echo "${GREEN}Granting policy add-role-to-user cluster-monitoring-view ${ENDCOLOR} " 
    # oc -n ${NAMESPACE} policy add-role-to-user cluster-monitoring-view  ${USER3}

# Apply permissions to test-user - you must be logged in a cluster administratior (e.g. kubeadmin)
    echo "\n** Granting permission for  \n user: ${GREEN} ${USER4}  ${ENDCOLOR}   \n namepsace: ${GREEN} ${NAMESPACE} ${ENDCOLOR}\n "
    
    # echo "${GREEN}Granting policy add-role-to-user view ${ENDCOLOR}  " 
    oc -n ${NAMESPACE} policy add-role-to-user view ${USER4}
    
    # echo "${GREEN}Granting policy add-role-to-user cluster-logging-application-view ${ENDCOLOR}  " 
    # oc -n ${NAMESPACE} policy add-role-to-user cluster-logging-application-view ${USER4}
    
    # echo "${GREEN}Granting policy add-role-to-user monitoring-rules-edit ${ENDCOLOR}  " 
    # oc -n ${NAMESPACE} policy add-role-to-user monitoring-rules-edit ${USER4}
    
    # echo "${GREEN}Granting policy add-role-to-user cluster-monitoring-view ${ENDCOLOR} " 
    # oc -n ${NAMESPACE} policy add-role-to-user cluster-monitoring-view  ${USER4}

# Apply permissions to test-user - you must be logged in a cluster administratior (e.g. kubeadmin)
    echo "\n** Granting permission for  \n user: ${GREEN} ${USER5}  ${ENDCOLOR}   \n namepsace: ${GREEN} ${NAMESPACE} ${ENDCOLOR}\n "
    
    # echo "${GREEN}Granting policy add-role-to-user admin ${ENDCOLOR}  " 
    oc -n ${NAMESPACE} policy add-role-to-user admin ${USER5}
    
    # echo "${GREEN}Granting policy add-role-to-user cluster-logging-application-view ${ENDCOLOR}  " 
    # oc -n ${NAMESPACE} policy add-role-to-user cluster-logging-application-view ${USER5}
    
    # echo "${GREEN}Granting policy add-role-to-user monitoring-rules-edit ${ENDCOLOR}  " 
    # oc -n ${NAMESPACE} policy add-role-to-user monitoring-rules-edit ${USER5}
    
    # echo "${GREEN}Granting policy add-role-to-user cluster-monitoring-view ${ENDCOLOR} " 
    # oc -n ${NAMESPACE} policy add-role-to-user cluster-monitoring-view  ${USER5}

# Apply permissions to test-user - you must be logged in a cluster administratior (e.g. kubeadmin)
    echo "\n** Granting permission for  \n user: ${GREEN} ${USER6}  ${ENDCOLOR}   \n namepsace: ${GREEN} ${NAMESPACE} ${ENDCOLOR}\n "
    
    # no permissions to validate list page without project dropdown and create button disabled

# Open browser for UI 
    echo "** Openning Browser to OCP UI, here are your credentials: ** \n"
    echo "username: ${GREEN} ${USER1} ${ENDCOLOR}"
    echo "password: ${GREEN} password ${ENDCOLOR} \n"
    echo "username: ${GREEN} ${USER2} ${ENDCOLOR}"
    echo "password: ${GREEN} password ${ENDCOLOR} \n"
    echo "username: ${GREEN} ${USER3} ${ENDCOLOR}"
    echo "password: ${GREEN} password ${ENDCOLOR} \n"
    echo "username: ${GREEN} ${USER4} ${ENDCOLOR}"
    echo "password: ${GREEN} password ${ENDCOLOR} \n"
    echo "username: ${GREEN} ${USER5} ${ENDCOLOR}"
    echo "password: ${GREEN} password ${ENDCOLOR} \n"
    echo "username: ${GREEN} ${USER6} ${ENDCOLOR}"
    echo "password: ${GREEN} password ${ENDCOLOR} \n"

    sleep 3s 

    open $(oc whoami --show-console)
