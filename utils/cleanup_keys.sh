#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}"/../SET

# First - need to activate service account
# gcloud auth activate-service-account --key-file ...


# Cleaning up the keys
for i in $(gcloud compute os-login ssh-keys list --format="table[no-heading](value.fingerprint)"); do
  echo $i;
  gcloud compute os-login ssh-keys remove --key $i || true;
done