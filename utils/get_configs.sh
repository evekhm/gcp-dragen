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
  INPUT_FILE=$1
  OUTPUT_FILE=$2
  sed 's|__IMAGE__|'"$IMAGE_URI"'|g;
      s|__JXE_APP__|'"$JXE_APP"'|g;
      s|__OUT_BUCKET__|'"$OUTPUT_BUCKET_NAME"'|g;
      s|__IN_BUCKET__|'"$INPUT_BUCKET_NAME"'|g;
      s|__CONFIG_BUCKET__|'"$CONFIG_BUCKET_NAME"'|g;
      s|__DATA_BUCKET__|'"$DATA_BUCKET_NAME"'|g;
      ' "${INPUT_FILE}" > "${OUTPUT_FILE}"
}

echo "Preparing config files"

# CRAM
substitute "${WDIR}/../config/cram/cram_config_310.sample.json" "${WDIR}/../config/cram/cram_config_310.json"
substitute "${WDIR}/../config/cram/cram_config_403.sample.json" "${WDIR}/../config/cram/cram_config_403.json"
substitute "${WDIR}/../config/cram/NA12878_batch.sample.txt" "${WDIR}/../config/cram/NA12878_batch.txt"
substitute "${WDIR}/../config/cram/batch_config_403.sample.json" "${WDIR}/../config/cram/batch_config_403.json"
substitute "${WDIR}/../config/cram/batch_config_310.sample.json" "${WDIR}/../config/cram/batch_config_310.json"


gsutil cp "${WDIR}/../config/cram/cram_config_310.json" gs://"$CONFIG_BUCKET_NAME"/
gsutil cp "${WDIR}/../config/cram/cram_config_403.json" gs://"$CONFIG_BUCKET_NAME"/
gsutil cp "${WDIR}/../config/cram/batch_config_403.json" gs://"$INPUT_BUCKET_NAME/cram_test/403/batch_config.json"
gsutil cp "${WDIR}/../config/cram/batch_config_310.json" gs://"$INPUT_BUCKET_NAME/cram_test/310/batch_config.json"

gsutil cp "${WDIR}/../config/cram/NA12878_batch.txt" gs://"$INPUT_BUCKET_NAME"/cram_test/


# FASTQ LIST
substitute "${WDIR}/../config/fastq_list/fastq_list_config.sample.json" "${WDIR}/../config/fastq_list/fastq_list_config.json"
substitute "${WDIR}/../config/fastq_list/batch_config.sample.json" "${WDIR}/../config/fastq_list/batch_config.json"

gsutil cp "${WDIR}/../config/fastq_list/batch_config.json" gs://"$INPUT_BUCKET_NAME"/fastq_list_test/
gsutil cp "${WDIR}/../config/fastq_list/fastq_list.csv" gs://"$INPUT_BUCKET_NAME"/fastq_list_test/
gsutil cp "${WDIR}/../config/fastq_list/fastq_list_config.json" gs://"$CONFIG_BUCKET_NAME"/


# FASTQ
substitute "${WDIR}/../config/fastq/fastq_config.sample.json" "${WDIR}/../config/fastq/fastq_config.json"
substitute "${WDIR}/../config/fastq/batch_config.sample.json" "${WDIR}/../config/fastq/batch_config.json"

gsutil cp "${WDIR}/../config/fastq/fastq_config.json" gs://"$CONFIG_BUCKET_NAME"/
gsutil cp "${WDIR}/../config/fastq/batch_config.json" gs://"$INPUT_BUCKET_NAME"/fastq_test/