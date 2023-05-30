#!/bin/bash
set -e # Exit if error is detected during pipeline execution => terraform failing
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}"/SET

SCRIPT=$1

# Hard-coded Input files
export ILLUMINA_INPUT1="s3://${INPUT_BUCKET_NAME}/inputs/HG002.novaseq.pcr-free.35x.R1.fastq.ora"
export ILLUMINA_INPUT2="s3://${INPUT_BUCKET_NAME}/inputs/HG002.novaseq.pcr-free.35x.R2.fastq.ora"
export ILLUMINA_R="s3://${INPUT_BUCKET_NAME}/references/hg38_alt_masked_cnv_graph_hla_rna-8-r2.0-1"
export ILLUMINA_ORA_REF="s3://${INPUT_BUCKET_NAME}/references/lenadata"

# Retrieving Secrets
export S3_ACCESS_KEY=$(gcloud secrets versions access latest --secret="$S3_SECRET" --project=$PROJECT_ID | jq ".access_key" | tr -d '"')
export S3_SECRET_KEY=$(gcloud secrets versions access latest --secret="$S3_SECRET" --project=$PROJECT_ID | jq ".access_secret" | tr -d '"')
export ILLUMINA_LICENSE=$(gcloud secrets versions access latest --secret="$LICENCE_SECRET" --project=$PROJECT_ID | jq ".illumina_license" | tr -d '"')
export JXE_USERNAME=$(gcloud secrets versions access latest --secret="$LICENCE_SECRET" --project=$PROJECT_ID | jq ".jxe_username" | tr -d '"')
export JXE_APIKEY=$(gcloud secrets versions access latest --secret="$LICENCE_SECRET" --project=$PROJECT_ID | jq ".jxe_apikey" | tr -d '"')


if [ -z "$S3_ACCESS_KEY" ]; then
  echo "Error: S3_ACCESS_KEY could not be retrieved from $S3_SECRET secret"
  exit
fi

if [ -z "$S3_SECRET_KEY" ]; then
  echo "Error: S3_SECRET_KEY could not be retrieved from $S3_SECRET secret"
  exit
fi

if [ -z "$JXE_APIKEY" ]; then
  echo "Error: JXE_APIKEY could not be retrieved from $LICENCE_SECRET secret"
  exit
fi

if [ -z "$ILLUMINA_LICENSE" ]; then
  echo "Error: ILLUMINA_LICENSE could not be retrieved from $LICENCE_SECRET secret"
  exit
fi

if [ -z "$JXE_USERNAME" ]; then
  echo "Error: JXE_USERNAME could not be retrieved from $LICENCE_SECRET secret"
  exit
fi


date_str=$(date +%s )
"${SCRIPT}" \
 --s3-access-key "$S3_ACCESS_KEY" \
 --s3-secret-key "$S3_SECRET_KEY" \
 --\
 -f \
  -1 "$ILLUMINA_INPUT1" \
  -2 "$ILLUMINA_INPUT2" \
  --RGID HG002 \
  --RGSM HG002 \
  --ora-reference "$ILLUMINA_ORA_REF" -r "$ILLUMINA_R" \
  --enable-map-align true \
  --enable-map-align-output true \
  --enable-duplicate-marking true \
  --output-format CRAM \
  --enable-variant-caller true \
  --enable-vcf-compression true \
  --vc-emit-ref-confidence GVCF \
  --vc-enable-vcf-output true \
  --enable-cnv true \
  --cnv-enable-self-normalization true \
  --cnv-segmentation-mode slm \
  --enable-cyp2d6 true \
  --enable-cyp2b6 true \
  --enable-gba true \
  --enable-smn true \
  --enable-star-allele true \
  --enable-sv true \
  --repeat-genotype-enable true \
  --repeat-genotype-use-catalog expanded \
  --output-file-prefix HG002_pure \
  --output-directory s3://"${OUTPUT_BUCKET_NAME}"/"${date_str}" \
  --intermediate-results-dir /tmp/whole_genome/temp \
  --logging-to-output-dir true \
  --syslogging-to-output-dir true \
  --lic-server https://"$ILLUMINA_LICENSE"@license.edicogenome.com