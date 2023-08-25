#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
set -x
cat /etc/os-release
oc config view
oc projects
python --version
pushd /tmp
python -m virtualenv ./venv_qe
source ./venv_qe/bin/activate

git clone https://github.com/cloud-bulldozer/e2e-benchmarking --depth=1
pushd e2e-benchmarking/workloads/kube-burner-ocp-wrapper

current_worker_count=$(oc get nodes --no-headers -l node-role.kubernetes.io/worker=,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/workload!= --output jsonpath="{.items[?(@.status.conditions[-1].type=='Ready')].status.conditions[-1].type}" | wc -w | xargs)
set_pods_per_node(){
    current_pod_count=$(oc get nodes --selector="node-role.kubernetes.io/worker=,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/workload!=" -o name | cut -d '/' -f 2 | xargs -I {} oc get pods --field-selector=status.phase=Running,spec.nodeName={} -o name -A | wc -l)
    PODS_PER_NODE=$(( (2 + current_pod_count) / current_worker_count + 1 ))
}

set_pods_per_node
export EXTRA_FLAGS="--pods-per-node=$PODS_PER_NODE"
export WORKLOAD=node-density-cni
./run.sh

set_pods_per_node
export EXTRA_FLAGS="--pods-per-node=$PODS_PER_NODE --pod-ready-threshold=180000ms"
export WORKLOAD=node-density
./run.sh

set_pods_per_node
export EXTRA_FLAGS="--pods-per-node=$PODS_PER_NODE --namespaced-iterations=true --iterations-per-namespace=1"
export WORKLOAD=node-density-heavy
./run.sh

export ITERATIONS=1
export WORKLOAD=cluster-density-v2
export EXTRA_FLAGS="--churn=true --churn-duration=1m"
./run.sh
