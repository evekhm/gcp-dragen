#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}"/../SET

echo "Creating Service Account Key for ${JOB_SERVICE_ACCOUNT}"
export KEY=${PROJECT_ID}_${SA_JOB_NAME}.json
gcloud iam service-accounts keys create ${KEY} \
        --iam-account=${JOB_SERVICE_ACCOUNT}

echo "Activating Service Account"
gcloud auth activate-service-account --key-file ${KEY}

echo "Cleaning up ssh keys"
for i in $(gcloud compute os-login ssh-keys list --format="table[no-heading](value.fingerprint)"); do
  echo $i;
  gcloud compute os-login ssh-keys remove --key $i || true;
done