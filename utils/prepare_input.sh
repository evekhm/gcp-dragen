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
source "$DIR/../SET"  > /dev/null 2>&1

PARALLEL=10
BATCH_SIZE=20
INPUT="gs://$INPUT_BUCKET_NAME/cram/input_list/100_samples.txt"

#PARALLEL=5
#BATCH_SIZE=10
#INPUT="gs://$INPUT_BUCKET_NAME/cram/input_list/30_samples.txt"
export DEBUG=true

#echo "-p $PARALLEL -b $BATCH_SIZE -c gs://$CONFIG_BUCKET_NAME/cram_config_378.json \
#                      -o ${TEST_RUN_DIR} -s ${INPUT} --dryrun"
python "${DIR}/prepare_input/main.py" -p $PARALLEL -b $BATCH_SIZE -c gs://$CONFIG_BUCKET_NAME/cram_config_378.json \
                -o ${TEST_RUN_DIR} -s ${INPUT} --dryrun