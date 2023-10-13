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
bash "$DIR/../setup/check_setup.sh"
retVal=$?
if [ $retVal -eq 2 ]; then
  exit 2
fi

# get parameters
while getopts n:s:l:b:a: flag
do
  case "${flag}" in
    n) SCRIPT=${OPTARG};;
    s) SAMPLE_ID=${OPTARG};;
    l) LABEL=${OPTARG};;
    b) BEFORE_TIME=${OPTARG};;
    a) AFTER_TIME=${OPTARG};;
    *) usage;;
  esac
done


if [ -z "$SCRIPT" ]; then
  echo " Usage: ./run_query.sh -n <QUERY_NAME> [ -s <sample_id>] [-l <job-label>] [-a <task_created_after-this-time>]  [-b <task_created_before-this-time>] "
  echo " QUERY_NAMEs:"
  echo "     - count   - Summary of the samples with counts per status "
  echo "     - samples - Detailed summary of samples with the latest statuses"
  echo "     - sample  - Detailed summary with all statuses (usually done per sample)"
  echo " Example: "
  echo "      sql-scripts/run_query.sh -n sample -s NA21 -l job1 -a 2023-10-07T03:23:10"
  exit
fi

SAMPLE_FILTER=" --parameter=SAMPLE_ID:STRING:$SAMPLE_ID"
LABEL_FILTER=" --parameter=LABEL:STRING:$LABEL"


if [ -z "$AFTER_TIME" ]; then
  AFTER_TIME="2016-12-07 08:00:00"
fi
AFTER_TIME=" --parameter='AFTER_TIME:TIMESTAMP:$AFTER_TIME' "

if [ -z "$BEFORE_TIME" ]; then
  BEFORE_TIME="2100-12-07 08:00:00"
fi
BEFORE_TIME=" --parameter='BEFORE_TIME:TIMESTAMP:$BEFORE_TIME' "

echo bq query --project_id="$PROJECT_ID" --dataset_id="$DATASET"  --nouse_legacy_sql  "$LABEL_FILTER" "$SAMPLE_FILTER" "$AFTER_TIME" "$BEFORE_TIME" --max_rows=10000  --flagfile="${DIR}/${SCRIPT}.sql" > query
bash ./query 2> /dev/null
