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

WDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "${WDIR}/../SET"

function substitute(){
  INPUT_FILE="$1"
  echo "Substituting $INPUT_FILE"
  OUTPUT_FILE="${INPUT_FILE//.sample/}"
#  echo $INPUT_FILE
#  echo $OUTPUT_FILE
  sed 's|__IMAGE__|'"$IMAGE_URI"'|g;
      s|__JXE_APP__|'"$JXE_APP"'|g;
      s|__OUT_BUCKET__|'"$OUTPUT_BUCKET_NAME"'|g;
      s|__IN_BUCKET__|'"$INPUT_BUCKET_NAME"'|g;
      s|__CONFIG_BUCKET__|'"$CONFIG_BUCKET_NAME"'|g;
      s|__DATA_BUCKET__|'"$DATA_BUCKET_NAME"'|g;
      s|__JOBS_INFO__|'"$JOBS_INFO"'|g;
      ' "${INPUT_FILE}" > "${OUTPUT_FILE}"
}

function copy_files(){
  f=$1
  DIRNAME=$(dirname "$f")
  BASENAME=$(basename "$DIRNAME")
  PARENTDIR="$(dirname "$DIRNAME")"
  PARENT=$(basename "$PARENTDIR")
  echo $DIRNAME $BASENAME $PARENT
  GCS="gs://$INPUT_BUCKET_NAME/$PARENT/$BASENAME/"
  echo "Copying $f to $GCS"
  gsutil cp  "$f" "$GCS"
}

echo "Preparing config files"

"${WDIR}"/create_input_samples_list.sh 10 "${WDIR}"/../config/cram/input_list/1000_samples.txt

# Substitute all .sample
export -f substitute
find "${WDIR}/../config" -name '*.sample.*'  -exec bash -c 'substitute "$0"' {} \;

#Copy config.json files to config bucket
find "${WDIR}/../config" -name "*.json" -type f ! -name '*sample.json' ! -name 'batch_*.json' | gsutil -m cp -I gs://"$CONFIG_BUCKET_NAME"

# Substitute and copy batch_config files
export -f copy_files
find "${WDIR}/../config" -type f ! -name '*.sample.*' \( -name '*.txt' -o -name 'batch_*.json' -o -name '*.csv' \) -exec bash -c 'copy_files "$0"' {} \;

gsutil cp "${WDIR}/../data/status_header.csv" gs://"$OUTPUT_BUCKET_NAME/status/"
