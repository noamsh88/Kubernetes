#!/bin/bash
set -ex
###########################################################################################
# Script actions:
# 1. Generate cluster nodes, pods and services status
# 2. Generate kubectl logs and describe per pod name in case pod in not Running state
# 3. Generate Docker images and running containers of script server
# 4. Generate docker logs of all containers
# 5. Pack output logs directory to tar.gz file
###########################################################################################

# Script Configurations
export DATE=`date +%Y%m%d_%H%M%S`
export SCRIPT_DIR=$(cd $(dirname $BASH_SOURCE[0]) &>/dev/null && pwd)
export OPT_LOG_DIR=${SCRIPT_DIR}/kubernetes_cluster_logs_${DATE}
export OPT_LOG=${OPT_LOG_DIR}/kubernetes_cluster_logs_`hostname`_${DATE}.log
mkdir -p ${OPT_LOG_DIR}/docker_logs
mkdir -p ${OPT_LOG_DIR}/kubernetes/kubectl_describe
mkdir -p ${OPT_LOG_DIR}/kubernetes/kubectl_logs

# Kubernetes
kubectl get nodes | tee -a ${OPT_LOG}
kubectl get pods -A | tee -a ${OPT_LOG}
kubectl get svc -A | tee -a ${OPT_LOG}

# Extract kubernetes logs
for POD_NAME in $(kubectl get pods -A --no-headers  | awk '{print $2}')
do
  POD_NAMESPACE=$(kubectl get pods -A --no-headers | grep ${POD_NAME} | awk '{print $1}' )
  POD_STATE=$(kubectl get pods -A --no-headers | grep ${POD_NAME} | awk '{print $4}' )

  # Generate kubectl logs and describe per pod name in case pod in not Running state
  if [[ "${POD_STATE}" != "Running" ]]
  then
    echo "${POD_NAMESPACE}        ${POD_NAME}       ${POD_STATE}"
    # kubectl logs
    kubectl logs ${POD_NAME} -n ${POD_NAMESPACE} >& ${OPT_LOG_DIR}/kubernetes/kubectl_logs/${POD_NAMESPACE}_${POD_NAME}_pod_logs_${DATE}.log || true
    # kubectl describe
    kubectl describe pod ${POD_NAME} -n ${POD_NAMESPACE} >& ${OPT_LOG_DIR}/kubernetes/kubectl_describe/${POD_NAMESPACE}_${POD_NAME}_pod_describe_${DATE}.log
  fi

done

# Docker
docker images | tee -a ${OPT_LOG}
docker ps | tee -a ${OPT_LOG}

# Extract docker logs of all containers
for CONTAINER_ID in $(docker container ls | awk '{print $1}' | grep -v CONTAINER)
do
  docker logs ${CONTAINER_ID} >& ${OPT_LOG_DIR}/docker_logs/${CONTAINER_ID}_$(hostname)_container_logs_${DATE}.log
done

# Pack Output log directory
cd ${SCRIPT_DIR}
OPT_DIR_NAME=`basename ${OPT_LOG_DIR}`
tar -cvf ${OPT_DIR_NAME}.tar ${OPT_DIR_NAME}
gzip ${OPT_DIR_NAME}.tar

echo -e "\n Kubernetes and docker containers logs extracted and packed to following tar.gz file: "
echo "${OPT_LOG_DIR}.tar.gz"
