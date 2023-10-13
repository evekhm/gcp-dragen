#!/bin/bash
# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script automates all the setup steps after creating code skeleton using
# the Solutions template and set up all components to a brand-new Google Cloud
# project.
set -e # Exit if error is detected during pipeline execution => terraform failing
CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

while getopts ad flag
do
    case "${flag}" in
        a) AUTO_APPROVE=true;;
        d) DISABLE_POLICY=true;;
        *) usage;;
    esac
done

usage()
{
    echo "Usage: $0
        [ -a Auto-Approve Terraform  ]
        [ -d Disable required organization plocies  ]
"
    echo "-a: Optional set to auto-approve terraform changes. By default will ask explicitly"
    echo "-d: Optionally set to modify required organization policies. Otherwise should be done separately "
    exit 2
}

# Set up environment variables.
check_env_vars() {
  bash "$CDIR/check_setup.sh"
  retVal=$?
  if [ $retVal -eq 2 ]; then
    exit 2
  fi
}

# Set up gcloud CLI
setup_gcloud() {
  gcloud config set project "${PROJECT_ID}" --quiet
#  sudo apt-get install google-cloud-sdk google-cloud-sdk-gke-gcloud-auth-plugin
#  gcloud components install alpha gke-gcloud-auth-plugin --quiet

}


# Create a Service Account for Terraform impersonating and grant Storage admin to the current user IAM.
# Create Terraform State file in GCS bucket.
setup_terraform() {
  bash "${CDIR}"/setup_terraform.sh
  
  echo "Wait 30 seconds for IAM updates..."
  sleep 30
  # List all buckets.
  gcloud storage ls --project="${PROJECT_ID}"
  echo "TF_BUCKET_NAME = ${TF_BUCKET_NAME}"
  echo
}

# Deploy Cloud Functions
deploy() {
  bash "${CDIR}"/deploy.sh
}

# Run terraform to set up all GCP resources. (Setting up GKE by default)
init_foundation() {
  # Init / Apply Terraform Foundation with auto-approve
  bash "${CDIR}"/init_foundation.sh "$@"
}

# Update GCP Organizational policies
update_gcp_org_policies() {
  if [ -n "${DISABLE_POLICY}" ]; then
    bash "${CDIR}"/update_gcp_org_policies.sh
  fi
}

check_env_vars

setup_gcloud

update_gcp_org_policies

setup_terraform

#otherwise here always getting  "permission": "iam.serviceAccounts.getAccessToken"

init_foundation "$@"

deploy


