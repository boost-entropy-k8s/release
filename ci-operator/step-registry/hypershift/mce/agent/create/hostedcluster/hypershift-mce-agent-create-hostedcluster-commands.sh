#!/bin/bash

set -exuo pipefail

trap 'FRC=$?; [[ $FRC != 0 ]] && debug' EXIT TERM

debug() {
  oc get --namespace=local-cluster hostedcluster/${CLUSTER_NAME} -o yaml
  oc get pod -n local-cluster-${CLUSTER_NAME} -oyaml
  oc logs -n hypershift -lapp=operator --tail=-1 -c operator | grep -v "info" > $ARTIFACT_DIR/hypershift-errorlog.txt
}

if [ -f "${SHARED_DIR}/proxy-conf.sh" ] ; then
  source "${SHARED_DIR}/proxy-conf.sh"
fi

MCE_VERSION=$(oc get "$(oc get multiclusterengines -oname)" -ojsonpath="{.status.currentVersion}" | cut -c 1-3)
HYPERSHIFT_NAME=hcp
if (( $(awk 'BEGIN {print ("'"$MCE_VERSION"'" < 2.4)}') )); then
  echo "MCE version is less than 2.4"
  HYPERSHIFT_NAME=hypershift
fi

arch=$(arch)
if [ "$arch" == "x86_64" ]; then
  downURL=$(oc get ConsoleCLIDownload ${HYPERSHIFT_NAME}-cli-download -o json | jq -r '.spec.links[] | select(.text | test("Linux for x86_64")).href') && curl -k --output /tmp/${HYPERSHIFT_NAME}.tar.gz ${downURL}
  cd /tmp && tar -xvf /tmp/${HYPERSHIFT_NAME}.tar.gz
  chmod +x /tmp/${HYPERSHIFT_NAME}
  cd -
fi

CLUSTER_NAME="$(echo -n $PROW_JOB_ID|sha256sum|cut -c-20)"
CLUSTER_NAMESPACE=local-cluster-${CLUSTER_NAME}
echo "$(date) Creating HyperShift cluster ${CLUSTER_NAME}"
oc create ns "${CLUSTER_NAMESPACE}"
BASEDOMAIN=$(oc get dns/cluster -ojsonpath="{.spec.baseDomain}")
echo "extract secret/pull-secret"
oc extract secret/pull-secret -n openshift-config --to=/tmp --confirm
echo "check HYPERSHIFT_HC_RELEASE_IMAGE, if not set, use mgmt-cluster playload image"
#RELEASE_IMAGE=${HYPERSHIFT_HC_RELEASE_IMAGE:-$RELEASE_IMAGE_LATEST}

IP_STACK_COMMAND=""
if [[ "${IP_STACK}" == "v4v6" ]]; then
  IP_STACK_COMMAND="--default-dual"
fi

/tmp/${HYPERSHIFT_NAME} --version
/tmp/${HYPERSHIFT_NAME} create cluster agent ${EXTRA_ARGS} ${IP_STACK_COMMAND} \
  --name=${CLUSTER_NAME} \
  --pull-secret=/tmp/.dockerconfigjson \
  --agent-namespace="${CLUSTER_NAMESPACE}" \
  --namespace local-cluster \
  --base-domain=${BASEDOMAIN} \
  --api-server-address=api.${CLUSTER_NAME}.${BASEDOMAIN} \
  --image-content-sources "${SHARED_DIR}/mgmt_icsp.yaml" \
  --ssh-key="${SHARED_DIR}/id_rsa.pub"
### workaround for https://issues.redhat.com/browse/DPTP-4024
### --release-image ${RELEASE_IMAGE} use default release-image

if (( $(awk 'BEGIN {print ("'"$MCE_VERSION"'" < 2.4)}') )); then
  echo "MCE version is less than 2.4"
  oc annotate hostedclusters -n local-cluster ${CLUSTER_NAME} "cluster.open-cluster-management.io/managedcluster-name=${CLUSTER_NAME}" --overwrite
  oc apply -f - <<EOF
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  annotations:
    import.open-cluster-management.io/hosting-cluster-name: local-cluster
    import.open-cluster-management.io/klusterlet-deploy-mode: Hosted
    open-cluster-management/created-via: other
  labels:
    cloud: auto-detect
    cluster.open-cluster-management.io/clusterset: default
    name: ${CLUSTER_NAME}
    vendor: OpenShift
  name: ${CLUSTER_NAME}
spec:
  hubAcceptsClient: true
  leaseDurationSeconds: 60
EOF
fi

echo "Waiting for cluster to become available"
oc wait --timeout=30m --for=condition=Available --namespace=local-cluster hostedcluster/${CLUSTER_NAME}
echo "Cluster became available, creating kubeconfig"
/tmp/${HYPERSHIFT_NAME} create kubeconfig --namespace=local-cluster --name=${CLUSTER_NAME} >${SHARED_DIR}/nested_kubeconfig