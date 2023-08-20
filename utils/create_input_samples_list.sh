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
source "${DIR}"/../SET

COUNT=$1
OUTPUT=$2
# collaborator_sample_id	cram_file_ref
#NA12878-SmokeTest	s3://ek-broad-gp-dragen-demo/NA12878/NA12878.cram

if [ -z "$OUTPUT" ]; then
  OUTPUT="${DIR}/${COUNT}_samples.txt"
fi

if [ -z "$COUNT" ]; then
  COUNT=10
fi

echo "Generating $COUNT test samples into $OUTPUT file ..."

echo "collaborator_sample_id	cram_file_ref" > ${OUTPUT}
counter=0
while [ $counter -lt $COUNT ]
do
  SAMPLE="NA${counter}"
  PATH="s3://${DATA_BUCKET_NAME}/${SAMPLE}/${SAMPLE}.cram"
  echo "${SAMPLE} ${PATH}" >> ${OUTPUT}
  ((counter++))
done