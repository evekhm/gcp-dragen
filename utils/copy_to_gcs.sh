#!/bin/bash
set -e
if [ -z "$PROJECT_ID" ]; then
    echo "PROJECT_ID variable must be set, exiting.."
    exit 1
fi
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}"/SET

echo "uploading sample data to GCS. THis will take a while..."

PWD=$(pwd)
cd "${DIR}/data"
gsutil cp -r ./hg38+alt_masked+cnv+graph+hla+rna-8-r2.0-1 gs://${INPUT_BUCKET_NAME}/references/hg38_alt_masked_cnv_graph_hla_rna-8-r2.0-1
gsutil cp -r lenadata gs://${INPUT_BUCKET_NAME}/references/
gsutil cp HG002.novaseq.pcr-free.35x.R1.fastq.ora gs://${INPUT_BUCKET_NAME}/inputs/
gsutil cp HG002.novaseq.pcr-free.35x.R2.fastq.ora gs://${INPUT_BUCKET_NAME}/inputs/
echo "Done!"
cd "$PWD"