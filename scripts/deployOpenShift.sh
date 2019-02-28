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

# Initiating installation of OpenShift Container Platform using Ansible Playbook
echo $(date) " - Installing OpenShift Container Platform via Ansible Playbook"
runuser -l $SUDOUSER -c "ansible-playbook -e openshift_cloudprovider_azure_client_id=$AADCLIENTID -e openshift_cloudprovider_azure_client_secret=\"$AADCLIENTSECRET\" -e openshift_cloudprovider_azure_tenant_id=$TENANTID -e openshift_cloudprovider_azure_subscription_id=$SUBSCRIPTIONID -f 30 /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml"
if [ $? -eq 0 ]
then
    echo $(date) " - OpenShift Cluster installed successfully"
else
    echo $(date) " - OpenShift Cluster failed to install"
    exit 6
fi

echo $(date) " - Script complete"
