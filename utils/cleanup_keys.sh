#!/bin/bash
# Copyright 2023 Google LLC
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