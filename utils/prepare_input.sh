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
source "$DIR/../setup/init_env_vars.sh"  > /dev/null 2>&1

PARALLEL=10
BATCH_SIZE=20
INPUT_20="gs://$INPUT_BUCKET_NAME/cram/input_list/20_samples.txt"
INPUT_21="gs://$INPUT_BUCKET_NAME/cram/input_list/20_21_samples.txt"
INPUT_22="gs://$INPUT_BUCKET_NAME/cram/input_list/22_samples.txt"

export DEBUG=true

python3 "${DIR}/prepare_input/main.py" -p $PARALLEL -b $BATCH_SIZE \
  -c gs://$CONFIG_BUCKET_NAME/dryrun_config_ok.json -s ${INPUT_20} \
  -c gs://$CONFIG_BUCKET_NAME/dryrun_config_pass.json -s  ${INPUT_21} \
  -c gs://$CONFIG_BUCKET_NAME/dryrun_config_fail.json -s  ${INPUT_22} \
  -o ${TEST_RUN_DIR}
