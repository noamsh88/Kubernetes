#!/bin/bash
set -ev
############################################################
# Script deploy helm chart directory to kubernetes cluster #
############################################################
export HELM_CHART_DIR=$1
export VALUES_FILE=$2
export HELM_DEPLOYMENT_NAME=$3
export NAMESPACE=$4
export HELM_INSTALL_ARGS=$5

# Script Configurations
export DATE=`date +%Y%m%d_%H%M%S`
export SCRIPT_DIR=$(cd $(dirname $BASH_SOURCE[0]) &>/dev/null && pwd)
export LOG_DIR=${SCRIPT_DIR}/logs
mkdir -p ${LOG_DIR}
export LOG_PATH=${LOG_DIR}/helm-install-${HELM_DEPLOYMENT_NAME}-${NAMESPACE}-${DATE}.log
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export NC='\033[0m'

# Function checks every 30 sec for each pod related to deployment name
validate_pods_are_running()
{
  local HELM_DEPLOYMENT_NAME=$1

  for POD in `kubectl get pods -n ${NAMESPACE} | awk '{print $1}' | grep ${HELM_DEPLOYMENT_NAME}`
  do
    unset POD_STATUS

    # Validate every 30 seconds if pod is Running, while loop set to exit if taking more than 30 min)
    export startTime=$(date +%s)

    while  [[ ${POD_STATUS} != "Running" ]]
    do
      # Get pod status
      export POD_STATUS=`kubectl get pods --no-headers ${POD} -n ${NAMESPACE} | awk '{print $3}'`

      # Exit script if taking more than 30 min (1800 seconds) , deployment time should take up to 10 min
      export currentTime=$(date +%s)
      export duration=$(($currentTime-$startTime))
      if [[ ${duration} -gt 1800 ]]
      then
        echo -e ${RED} "Deployment of ${POD} pod is taking more time than usual, please check pods status, exiting.." >> ${LOG_PATH}
        echo -e ${NC}
        kubectl get pods ${POD} -n ${NAMESPACE}  >> ${LOG_PATH}
        exit 1
      fi

      sleep 30
    done # while
  done # for

}

### Pre-Install Validations ###
pre_install_validations(){
  # Validate non root unix account
  if [[ ${USER} == "root" ]]
  then
    echo -e ${RED} "Script to be executed as NON-root user" >> ${LOG_PATH}
    exit 1
  fi

  # Validate required variables values are set
  if [[ -z ${HELM_CHART_DIR} || -z ${VALUES_FILE} || -z ${HELM_DEPLOYMENT_NAME} || -z ${NAMESPACE} ]];then
    echo -e ${RED} "USAGE : `basename $0` <Helm Chart Directory Path> <Helm Chart values.yaml file path> <Helm Deployment Name> <Namespace> <Helm Install arguments(optional)>" | tee -a ${LOG_PATH}
    echo -e "\nExample: bash `basename $0` ~/k8s-cluster-apps-deployment/apache-airflow ~/k8s-cluster-apps-deployment/apache-airflow/values.yaml airflow airflow  \n " | tee -a ${LOG_PATH}
    exit 1
  fi

  # Validate if helm installed
  if [[ `which helm | wc -l` -eq 0 ]]
  then
    echo -e ${RED} "helm utility NOT FOUND on `hostname` , please install it first and re-run.." >> ${LOG_PATH}
    exit 1
  fi

  # Validate if kubectl installed
  if [[ `which kubectl | wc -l` -eq 0 ]]
  then
    echo -e ${RED} "kubectl utility NOT FOUND on `hostname` , please install it first and re-run.." >> ${LOG_PATH}
    exit 1
  fi

  # Validate if helm chart directory exist
  if [ ! -d ${HELM_CHART_DIR} ]
  then
    echo -e ${RED} "${HELM_CHART_DIR} helm chart directory NOT FOUND, please set the correct helm chart path, exiting... " >> ${LOG_PATH} ; echo -e ${NC}
    exit 1
  fi

  # Validate if required values.yaml are exist under helm chart directory
  if  [[ ! -f ${VALUES_FILE} ]]
  then
    echo -e ${RED} "${VALUES_FILE} file NOT FOUND " >> ${LOG_PATH}
    echo "Please enter correct values.yaml file path from helm chart directory (${HELM_CHART_DIR}), exiting..." >> ${LOG_PATH}
    exit 1
  fi

}


### Main ###
pre_install_validations

# Delete helm deployment and namespace if exist
helm uninstall ${NAMESPACE} -n ${NAMESPACE} || true
kubectl delete namespace ${NAMESPACE} || true
sleep 10

# Install using custom values yaml files and package that packed from helm charts
echo "helm install -n ${NAMESPACE} --create-namespace --debug --timeout 10m0s ${HELM_DEPLOYMENT_NAME} -f ${VALUES_FILE} ${HELM_CHART_DIR} ${HELM_INSTALL_ARGS}"
helm install -n ${NAMESPACE} --create-namespace --debug --timeout 10m0s ${HELM_DEPLOYMENT_NAME} -f ${VALUES_FILE} ${HELM_CHART_DIR} ${HELM_INSTALL_ARGS} >> ${LOG_PATH}
validate_pods_are_running ${HELM_DEPLOYMENT_NAME}

kubectl get pods -n ${NAMESPACE}  | tee -a ${LOG_PATH}
echo -e ${GREEN} "${HELM_DEPLOYMENT_NAME} Succesfully Deployed To Kubernetes cluster on ${NAMESPACE} namespace" >> ${LOG_PATH}
echo -e ${NC} >> ${LOG_PATH}
