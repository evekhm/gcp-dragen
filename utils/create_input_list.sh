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
while getopts c:s:o: flag
do
  case "${flag}" in
    c) END_COUNT=${OPTARG};;
    s) START_COUNT=${OPTARG};;
    o) OUTPUT=${OPTARG};;
    *) usage;;
  esac
done

usage(){
  echo "Usage: $0
  [-s START_COUNT]
  -c END_COUNT
  -o OUTPUT_GCS_URI"
  echo "Example: create_input_list.sh -s 50 -c 100 -o gs://$PROJECT_ID-trigger/cram/test/samples.txt"
  exit
}

LOCAL_PATH="${DIR}/${END_COUNT}_samples.txt"

if [ -z "$END_COUNT" ] || [ -z "$OUTPUT" ]; then
  usage
fi

if [ -z "$START_COUNT" ]; then
  START_COUNT=0
fi

echo "Generating $START_COUNT-$END_COUNT test samples into $OUTPUT file ..."
# collaborator_sample_id	cram_file_ref
#NA12878-SmokeTest	s3://DATA_BUCKET_NAME/NA12878/NA12878.cram

echo "collaborator_sample_id	cram_file_ref" > ${LOCAL_PATH}
counter=$START_COUNT
while [ $counter -lt $END_COUNT ]
do
  SAMPLE="NA${counter}"
  SAMPLE_PATH="gs://${DATA_BUCKET_NAME}/${SAMPLE}/${SAMPLE}.cram"
  echo "${SAMPLE} ${SAMPLE_PATH}" >> ${LOCAL_PATH}
  ((counter++))
done

gsutil cp "$LOCAL_PATH" "$OUTPUT"