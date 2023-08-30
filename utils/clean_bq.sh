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
printf="${DIR}/print"
$printf "Cleaning up BQ..."

source "${DIR}/../SET"

if [[ -z "${PROJECT_ID}" ]]; then
  echo PROJECT_ID variable is not set. | tee -a "$LOG"
  exit
fi

if bq --location="${GCLOUD_REGION}" ls "${DATASET}" 2> /dev/null | grep  "${TASK_STATUS_TABLE_ID}"; then
  bq rm --quiet "${PROJECT_ID}":"${DATASET}"."${TASK_STATUS_TABLE_ID}"
fi

bq mk  --schema="${DIR}/../setup/bq_task_status_schema.json" --table "${DATASET}"."${TASK_STATUS_TABLE_ID}"  2> /dev/null
