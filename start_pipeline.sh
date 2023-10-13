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
PWD=$(pwd)

bash "$DIR/setup/check_setup.sh"
retVal=$?
if [ $retVal -eq 2 ]; then
  exit 2
fi

FOLDER=$1
if [ -z "$FOLDER" ]; then
  DEST="gs://${INPUT_BUCKET_NAME}/"
else
  DEST="gs://${INPUT_BUCKET_NAME}/${FOLDER}/"
fi

echo "Triggering Pipeline for $DEST"
gsutil cp "${DIR}/${START_PIPELINE_FILE}" "${DEST}"
