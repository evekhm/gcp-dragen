#!/bin/bash
WDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${WDIR}"/../setup/init_env_vars.sh

cat > env.sh <<EOF
NAME="dragen-job"
# Google Cloud zone (e.g. "us-central1")
ZONE="us-central1"
# list available versions with: ../tools/list-versions.sh
VERSION="1.0-rc.5"
# DRAGEN application (e.g "illumina-dragen_3_7_8n")
JARVICE_DRAGEN_APP="illumina-dragen_3_7_8n"
# secrets maintained by Google Secret Manager (https://cloud.google.com/secret-manager)
# format: projects/${PROJECT}/secrets/<secret-name>/versions/1
JARVICE_API_USERNAME_SECRET="projects/${PROJECT_ID}/secrets/${JARVICE_API_USERNAME_SECRET_NAME}/versions/1"
JARVICE_API_APIKEY_SECRET="projects/${PROJECT_ID}/secrets/${JARVICE_API_KEY_SECRET_NAME}/versions/1"
S3_ACCESS_KEY_SECRET="projects/${PROJECT_ID}/secrets/${S3_ACCESS_KEY_SECRET_NAME}/versions/1"
S3_SECRET_KEY_SECRET="projects/${PROJECT_ID}/secrets/${S3_SECRET_KEY_SECRET_NAME}/versions/1"
ILLUMINA_LIC_SERVER_SECRET="projects/${PROJECT_ID}/secrets/${ILLUMINA_LIC_SERVER_SECRET_NAME}/versions/1"

SERVICE_ACCOUNT=$JOB_SERVICE_ACCOUNT
DRAGEN_ARGS=(
-f
-r s3://dragen-ek-3-data/References/hg38_hash_3.7.8
--cram-input s3://dragen-ek-3-data/NA12878/NA12878.cram
--output-directory s3://dragen-ek-3-output/3_78/aggregation/NA12878-SmokeTest/ek
--intermediate-results-dir /tmp
--output-file-prefix NA12878-SmokeTest
--vc-sample-name NA12878-SmokeTest
--enable-map-align true
--enable-map-align-output true
--output-format CRAM
--enable-duplicate-marking true
--enable-variant-caller true
--vc-enable-vcf-output true
--vc-enable-prefilter-output true
--vc-emit-ref-confidence GVCF
--vc-frd-max-effective-depth 40
--vc-enable-joint-detection true
--qc-coverage-region-1 s3://dragen-ek-3-data/References/wgs_coverage_regions_hg38_minus_N_interval_list.bed
--qc-coverage-reports-1 cov_report
--qc-cross-cont-vcf s3://dragen-ek-3-data/References/SNP_NCBI_GRCh38.vcf
--qc-coverage-region-2 s3://dragen-ek-3-data/References/acmg59_allofus_19dec2019_GRC38_wGenes_NEW.bed
--qc-coverage-reports-2 cov_report
--qc-coverage-region-3 s3://dragen-ek-3-data/References/PGx_singleSite_GRCh38_09nov2020.bed
--qc-coverage-reports-3 cov_report
--vc-hard-filter \"'DRAGENHardQUAL:all:QUAL\\<5.0\\;LowDepth:all:DP\\<=1'\"
--qc-coverage-ignore-overlaps true
--qc-coverage-count-soft-clipped-bases true
--read-trimmers polyg
--soft-read-trimmers none
)
EOF