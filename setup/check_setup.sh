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

check_vars()
{
    var_names=("$@")
    for var_name in "${var_names[@]}"; do
        [ -z "${!var_name}" ] && echo "$var_name is unset." && var_unset=true
    done
    if [ -n "$var_unset" ]; then
      echo "Error: Environment not set properly. Make sure to run the following command prior to other steps:"
      echo ""
      echo "   ${DIR}/setup/init_env_vars.sh [env]"
      echo ""
      echo "Where [env] is optional environment to be selected (unless using the pre-defined default as specified in the setup/.env file)"
      exit 2
    fi
    return 0
}

# Some sublist is sufficient, no need to list all
check_vars PROJECT_ID DATASET CONFIG_BUCKET_NAME INPUT_BUCKET_NAME TEST_RUN_DIR TF_BUCKET_NAME \
TF_BUCKET_LOCATION SA_JOB_NAME JOB_SERVICE_ACCOUNT GCLOUD_REGION SLACK_API_TOKEN_SECRET_NAME \
START_PIPELINE_FILE TEST_RUN_DIR TASK_STATUS_TABLE_ID DATA_BUCKET_NAME ARTIFACTS_REPO COMMON_PACKAGE_NAME
