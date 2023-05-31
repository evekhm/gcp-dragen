#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/SET"
folder=$1
DEST=gs://$INPUT_BUCKET

if [ -n "$folder" ]; then
   DEST="${DEST}/${folder}"
fi
echo "Using $DEST"
gsutil -m cp -r gs://illumina-dragen-sample-data/references ${DEST}/
gsutil -m  cp -r gs://illumina-dragen-sample-data/inputs ${DEST}/
echo "Done!"