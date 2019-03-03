#!/bin/bash

echo $(date) " - Starting Script"

set -e

export SUDOUSER=$1
export PASSWORD="$2"
export MASTER=$3
export MASTERPUBLICIPHOSTNAME=$4
export MASTERPUBLICIPADDRESS=$5
export INFRA=$6
export NODE=$7
export NODECOUNT=$8
export INFRACOUNT=$9
export MASTERCOUNT=${10}
export ROUTING=${11}
export REGISTRYSA=${12}
export ACCOUNTKEY="${13}"
export METRICS=${14}
export LOGGING=${15}
export TENANTID=${16}
export SUBSCRIPTIONID=${17}
export AADCLIENTID=${18}
export AADCLIENTSECRET="${19}"
export RESOURCEGROUP=${20}
export LOCATION=${21}
export AZURE=${22}
export STORAGEKIND=${23}
export ENABLECNS=${24}
export CNS=${25}
export CNSCOUNT=${26}
export VNETNAME=${27}
export NODENSG=${28}
export NODEAVAILIBILITYSET=${29}
export MASTERCLUSTERTYPE=${30}
export PRIVATEIP=${31}
export PRIVATEDNS=${32}
export MASTERPIPNAME=${33}
export ROUTERCLUSTERTYPE=${34}
export INFRAPIPNAME=${35}
export IMAGEURL=${36}
export WEBSTORAGE=${37}
export CUSTOMROUTINGCERTTYPE=${38}
export CUSTOMMASTERCERTTYPE=${39}
export PROXYSETTING=${40}
export HTTPPROXYENTRY="${41}"
export HTTSPPROXYENTRY="${42}"
export NOPROXYENTRY="${43}"
export BASTION=$(hostname)

# Determine if Commercial Azure or Azure Government
CLOUD=$( curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2017-04-02&format=text" | cut -c 1-2 )
export CLOUD=${CLOUD^^}

# Create docker registry config based on Commercial Azure or Azure Government
if [[ $CLOUD == "US" ]]
then
    DOCKERREGISTRYYAML=dockerregistrygov.yaml
else
    DOCKERREGISTRYYAML=dockerregistrypublic.yaml
fi

# Install OpenShift Atomic Client
cd /root
mkdir .kube
runuser ${SUDOUSER} -c "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SUDOUSER}@${MASTER}-0:~/.kube/config /tmp/kube-config"
cp /tmp/kube-config /root/.kube/config
mkdir /home/${SUDOUSER}/.kube
cp /tmp/kube-config /home/${SUDOUSER}/.kube/config
chown --recursive ${SUDOUSER} /home/${SUDOUSER}/.kube
rm -f /tmp/kube-config
yum -y install atomic-openshift-clients

# Adding user to OpenShift authentication file
echo $(date) " - Adding OpenShift user"
runuser $SUDOUSER -c "ansible-playbook -f 30 ~/openshift-container-platform-playbooks/addocpuser.yaml"

# Assigning cluster admin rights to OpenShift user
echo $(date) " - Assigning cluster admin rights to user"
runuser $SUDOUSER -c "ansible-playbook -f 30 ~/openshift-container-platform-playbooks/assignclusteradminrights.yaml"

# Configure Docker Registry to use Azure Storage Account
echo $(date) " - Configuring Docker Registry to use Azure Storage Account"
runuser $SUDOUSER -c "ansible-playbook -f 30 ~/openshift-container-platform-playbooks/$DOCKERREGISTRYYAML"

# Reconfigure glusterfs storage class
if [ -f /home/$SUDOUSER/default-glusterfs-storage.yaml ]; then
    runuser -l $SUDOUSER -c "oc create -f /home/$SUDOUSER/default-glusterfs-storage.yaml"

    echo $(date) " - Sleep for 10"
    sleep 10
fi

# Ensuring selinux is configured properly
if [[ $ENABLECNS == "true" ]]
then
    # Setting selinux to allow gluster-fusefs access
    echo $(date) " - Setting selinux to allow gluster-fuse access"
    runuser -l $SUDOUSER -c "ansible all -o -f 30 -b -a 'sudo setsebool -P virt_sandbox_use_fusefs on'" || true
# End of CNS specific section
fi

# Adding some labels back because they go missing
echo $(date) " - Adding api and logging labels"
runuser -l $SUDOUSER -c  "oc label --overwrite nodes $MASTER-0 openshift-infra=apiserver"
runuser -l $SUDOUSER -c  "oc label --overwrite nodes --all logging-infra-fluentd=true logging=true"

# Restarting things so everything is clean before installing anything else
echo $(date) " - Rebooting cluster to complete installation"
runuser -l $SUDOUSER -c "ansible-playbook -f 30 ~/openshift-container-platform-playbooks/reboot-master.yaml"
runuser -l $SUDOUSER -c "ansible-playbook -f 30 ~/openshift-container-platform-playbooks/reboot-nodes.yaml"
sleep 20

# Installing Service Catalog, Ansible Service Broker and Template Service Broker
if [[ $AZURE == "true" || $ENABLECNS == "true" ]]
then
    runuser -l $SUDOUSER -c "ansible-playbook -e openshift_cloudprovider_azure_client_id=$AADCLIENTID -e openshift_cloudprovider_azure_client_secret=\"$AADCLIENTSECRET\" -e openshift_cloudprovider_azure_tenant_id=$TENANTID -e openshift_cloudprovider_azure_subscription_id=$SUBSCRIPTIONID -e openshift_enable_service_catalog=true -f 30 /usr/share/ansible/openshift-ansible/playbooks/openshift-service-catalog/config.yml"
fi

# Adding Open Sevice Broker for Azaure (requires service catalog)
if [[ $AZURE == "true" ]]
then
    oc new-project osba
    oc process -f https://raw.githubusercontent.com/Azure/open-service-broker-azure/master/contrib/openshift/osba-os-template.yaml  \
        -p ENVIRONMENT=AzurePublicCloud \
        -p AZURE_SUBSCRIPTION_ID=$SUBSCRIPTIONID \
        -p AZURE_TENANT_ID=$TENANTID \
        -p AZURE_CLIENT_ID=$AADCLIENTID \
        -p AZURE_CLIENT_SECRET=$AADCLIENTSECRET \
        | oc create -f -
fi

# Configure Metrics
if [[ $METRICS == "true" ]]
then
    sleep 30
    echo $(date) "- Deploying Metrics"
    if [[ $AZURE == "true" || $ENABLECNS == "true" ]]
    then
        runuser -l $SUDOUSER -c "ansible-playbook -e openshift_cloudprovider_azure_client_id=$AADCLIENTID -e openshift_cloudprovider_azure_client_secret=\"$AADCLIENTSECRET\" -e openshift_cloudprovider_azure_tenant_id=$TENANTID -e openshift_cloudprovider_azure_subscription_id=$SUBSCRIPTIONID -e openshift_metrics_install_metrics=True -e openshift_metrics_cassandra_storage_type=dynamic -f 30 /usr/share/ansible/openshift-ansible/playbooks/openshift-metrics/config.yml"
    else
        runuser -l $SUDOUSER -c "ansible-playbook -e openshift_metrics_install_metrics=True /usr/share/ansible/openshift-ansible/playbooks/openshift-metrics/config.yml"
    fi
    if [ $? -eq 0 ]
    then
        echo $(date) " - Metrics configuration completed successfully"
    else
        echo $(date) " - Metrics configuration failed"
        exit 11
    fi
fi

# Configure Logging

if [[ $LOGGING == "true" ]]
then
    sleep 60
    echo $(date) "- Deploying Logging"
    if [[ $AZURE == "true" || $ENABLECNS == "true" ]]
    then
        runuser -l $SUDOUSER -c "ansible-playbook -e openshift_cloudprovider_azure_client_id=$AADCLIENTID -e openshift_cloudprovider_azure_client_secret=\"$AADCLIENTSECRET\" -e openshift_cloudprovider_azure_tenant_id=$TENANTID -e openshift_cloudprovider_azure_subscription_id=$SUBSCRIPTIONID -e openshift_logging_install_logging=True -e openshift_logging_es_pvc_dynamic=true -f 30 /usr/share/ansible/openshift-ansible/playbooks/openshift-logging/config.yml"
    else
        runuser -l $SUDOUSER -c "ansible-playbook -e openshift_logging_install_logging=True -f 30 /usr/share/ansible/openshift-ansible/playbooks/openshift-logging/config.yml"
    fi
    if [ $? -eq 0 ]
    then
        echo $(date) " - Logging configuration completed successfully"
    else
        echo $(date) " - Logging configuration failed"
        exit 12
    fi
fi

# Configure cluster for private masters
if [[ $MASTERCLUSTERTYPE == "private" ]]
then
	echo $(date) " - Configure cluster for private masters"
	runuser -l $SUDOUSER -c "ansible-playbook -f 30 ~/openshift-container-platform-playbooks/activate-private-lb.31x.yaml"

	echo $(date) " - Delete Master Public IP if cluster is using private masters"
	az network public-ip delete -g $RESOURCEGROUP -n $MASTERPIPNAME
fi

# Delete Router / Infra Public IP if cluster is using private router
if [[ $ROUTERCLUSTERTYPE == "private" ]]
then
	echo $(date) " - Delete Router / Infra Public IP address"
	az network public-ip delete -g $RESOURCEGROUP -n $INFRAPIPNAME
fi

# Re-enabling requiretty
echo $(date) " - Re-enabling requiretty"
sed -i -e "s/# Defaults    requiretty/Defaults    requiretty/" /etc/sudoers

# Delete yaml files
echo $(date) " - Deleting unecessary files"
rm -rf /home/${SUDOUSER}/openshift-container-platform-playbooks

# Delete pem files
echo $(date) " - Delete pem files"
rm -rf /tmp/*.pem

echo $(date) " - Sleep for 30"
sleep 30

echo $(date) " - Script complete"
