#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}"/SET

#bash -e "${DIR}/utils/get_configs.sh" | tee -a "$LOG"
gsutil cp "${DIR}"/cloud_function/START_PIPELINE gs://"${INPUT_BUCKET_NAME}/cram_test/403/"