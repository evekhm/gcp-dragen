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
bash "$DIR/setup/check_setup.sh"
retVal=$?
if [ $retVal -eq 2 ]; then
  exit 2
fi

CONFIG=batch_config_ok

if [[ $1 == "fail" ]]; then
  CONFIG=batch_config_fail
fi

if [[ $1 == "pass" ]]; then
  CONFIG=batch_config_pass
fi

if [[ $1 == "ok" ]]; then
  CONFIG=batch_config_ok
fi

TRIGGER_FILE="${DIR}/tests/START_PIPELINE"
get_trigger_file(){
  sed 's|__CONFIG__|'"$1"'|g;
      ' "${DIR}/tests/START_PIPELINE.sample" > "${DIR}/tests/START_PIPELINE"
}


echo "CONFIG=$CONFIG"
get_trigger_file $CONFIG
cat "${TRIGGER_FILE}"
gsutil cp "${TRIGGER_FILE}" gs://"${INPUT_BUCKET_NAME}/cram/378-dryrun/"