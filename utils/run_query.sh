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
source "$DIR/../SET"

SCRIPT=$1

if [[ -z "${PROJECT_ID}" ]]; then
  echo PROJECT_ID variable is not set.
  exit
fi

if [ -z "$SCRIPT" ]; then
  echo " Usage: ./run_query.sh QUERY_NAME"
  echo " Options:"
  echo "     - samples"
  echo "     - sample [SAMPLE_NAME]"
  echo "     - count"
  exit
fi

#echo "Running $SCRIPT"
bq query --project_id="$PROJECT_ID" --dataset_id=$BIGQUERY_DATASET --nouse_legacy_sql --flagfile="${DIR}/${SCRIPT}.sql" 2> /dev/null


