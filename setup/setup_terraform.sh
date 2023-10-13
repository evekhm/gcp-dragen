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

WDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
bash "$WDIR/check_setup.sh"
retVal=$?
if [ $retVal -eq 2 ]; then
  exit 2
fi

declare -a EnvVars=(
  "PROJECT_ID"
  "ADMIN_EMAIL"
  "TF_BUCKET_NAME"
  "TF_BUCKET_LOCATION"
)

for variable in "${EnvVars[@]}"; do
  if [[ -z "${!variable}" ]]; then
    input_value=""
    while [[ -z "$input_value" ]]; do
      read -p "Enter the value for ${variable}: " input_value
      declare "${variable}=$input_value"
    done
  fi
done

BLUE=$(tput setaf 4)
RED=$(tput setaf 1)
NORMAL=$(tput sgr0)


create_bucket () {
  printf "PROJECT_ID=${PROJECT_ID}\n"
  printf "TF_BUCKET_NAME=${TF_BUCKET_NAME}\n"
  printf "TF_BUCKET_LOCATION=${TF_BUCKET_LOCATION}\n"

  gsutil ls "gs://${TF_BUCKET_NAME}" 2> /dev/null
  RETURN=$?
  if [[ $RETURN -gt 0 ]]; then
      echo "Bucket does not exist, creating gs://${TF_BUCKET_NAME}"
      gsutil mb -l $TF_BUCKET_LOCATION gs://$TF_BUCKET_NAME
      gsutil versioning set on gs://$TF_BUCKET_NAME
      export TF_BUCKET_NAME=$TF_BUCKET_NAME
      echo
  fi
}

enable_apis () {
  gcloud services enable cloudresourcemanager.googleapis.com --quiet
  gcloud services enable serviceusage.googleapis.com --quiet
  gcloud services enable iam.googleapis.com --quiet
  gcloud services enable iamcredentials.googleapis.com
  sleep 10
}

print_highlight () {
  printf "%s%s%s\n" "${BLUE}" "$1" "${NORMAL}"
}

# Create a Service Account for Terraform impersonating and grant Storage admin to the current user IAM.
setup_service_accounts_and_iam() {
  export CURRENT_USER=$(gcloud config list account --format "value(core.account)" | head -n 1)
  # Check if the current user is a service account.
  if [[ "${CURRENT_USER}" == *"iam.gserviceaccount.com"* ]]; then
    MEMBER_PREFIX="serviceAccount"
  else
    MEMBER_PREFIX="user"
  fi

  # Create TF runner services account and use it for impersonate.
  export TF_RUNNER_SA_EMAIL="terraform-runner@${PROJECT_ID}.iam.gserviceaccount.com"
  export GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=${TF_RUNNER_SA_EMAIL}

  SA_EXISTS=$(gcloud iam service-accounts list --filter="terraform-runner" | wc -l)
  if [ $SA_EXISTS = "0" ]; then
    gcloud iam service-accounts create "terraform-runner" --project=${PROJECT_ID}
  fi

  # Grant service account Token creator for current user.
  declare -a runnerRoles=(
    "roles/iam.serviceAccountTokenCreator"
    "roles/iam.serviceAccountUser"
  )
  for role in "${runnerRoles[@]}"; do
    echo "Adding IAM ${role} permissions to ${CURRENT_USER} for ${TF_RUNNER_SA_EMAIL}"
    gcloud iam service-accounts add-iam-policy-binding "${TF_RUNNER_SA_EMAIL}" --member="$MEMBER_PREFIX:${CURRENT_USER}" --role="$role"
  done

  # Bind the TF runner service account with required roles.
  declare -a runnerRoles=(
    "roles/owner"
    "roles/storage.admin"
  )
  for role in "${runnerRoles[@]}"; do
    echo "Adding IAM ${role} to ${TF_RUNNER_SA_EMAIL}..."
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${TF_RUNNER_SA_EMAIL}" --role="$role" --quiet
  done
}

enable_apis
create_bucket
setup_service_accounts_and_iam
print_highlight "Terraform state bucket: ${TF_BUCKET_NAME}"
