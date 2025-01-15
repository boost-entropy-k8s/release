#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# save the exit code for junit xml file generated in step gather-must-gather
# pre configuration steps before running installation, exit code 100 if failed,
# save to install-pre-config-status.txt
# post check steps after cluster installation, exit code 101 if failed,
# save to install-post-check-status.txt
EXIT_CODE=100
trap 'if [[ "$?" == 0 ]]; then EXIT_CODE=0; fi; echo "${EXIT_CODE}" > "${SHARED_DIR}/install-pre-config-status.txt"' EXIT TERM

echo "$(date -u --rfc-3339=seconds) - Enabling the IAM service account of minimal permissions for deploying OCP cluster into GCP shared VPC..."

# For now using the same service account as the user-tags testing, 
# but it is possible to use another service account in future. 
cp "${CLUSTER_PROFILE_DIR}/user_tags_sa.json" "${SHARED_DIR}/xpn_min_perm_passthrough.json"
