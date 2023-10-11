#! /bin/bash

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Jarvice
#export JXE_APP="illumina-dragen_4_0_3n"   # 4.0.3
#export JXE_APP="illumina-dragen_3_10_4n"  # 3.10.4
export JXE_APP="illumina-dragen_3_7_8n"    # 3.7.8 version
export ENTRYPOINT="/bin/sh"
export STUB="/usr/local/bin/entrypoint"
VERSION="1.0-rc.5"  # For version check https://github.com/nimbix/jarvice-dragen-batch/tree/master/tools/list-versions.sh
export IMAGE_URI="us-docker.pkg.dev/jarvice/images/jarvice-dragen-service:$VERSION"
export API_HOST="https://illumina.nimbix.net/api"
export JARVICE_MACHINE_TYPE="nx1"

# GCP
export GCLOUD_PROJECT=$PROJECT_ID
export GCLOUD_REGION="us-central1"
export GCLOUD_ZONE="us-central1-a"
export GCLOUD_IMAGE="atos-illumina-jxe-stub-rc"
export GCLOUD_IMAGE_PROJECT="atos-illumina-public"
export GCLOUD_BATCH_IMAGE_PROJECT="batch-custom-image"
export GCLOUD_MACHINE="e2-small"
export GCLOUD_INSTANCE="dragen"

export DATA_BUCKET_NAME=${PROJECT_ID}-data
export INPUT_BUCKET_NAME=${PROJECT_ID}-trigger
export OUTPUT_BUCKET_NAME=${PROJECT_ID}-output
export CONFIG_BUCKET_NAME=${PROJECT_ID}-config

export GCLOUD_NETWORK="default"
export GCLOUD_SUBNET="default"

# Batch
export JOB_NAME_SHORT="job-dragen"
export JOB_NAME="projects/${PROJECT_ID}/locations/${GCLOUD_REGION}/jobs/${JOB_NAME_SHORT}"
export SA_JOB_NAME="illumina-script-sa"
export JOB_SERVICE_ACCOUNT=${SA_JOB_NAME}@${PROJECT_ID}.iam.gserviceaccount.com
export SA_NAME_STORAGE="storage-admin"
export SA_EMAIL_STORAGE=${SA_NAME_STORAGE}@${PROJECT_ID}.iam.gserviceaccount.com


# Secrets
export S3_SECRET="s3_hmac_secret_key"
export LICENSE_SECRET="license_secret_key"
# new batch Flow
export S3_ACCESS_KEY_SECRET_NAME="batchS3AccessKey"
export S3_SECRET_KEY_SECRET_NAME="batchS3SecretKey"
export ILLUMINA_LIC_SERVER_SECRET_NAME="illuminaLicServer"
export JARVICE_API_KEY_SECRET_NAME="jarviceApiKey"
export JARVICE_API_USERNAME_SECRET_NAME="jarviceApiUsername"

# Cloud Function Run Batch
CLOUD_FUNCTIONS_DIR="${ROOT_DIR}/../cloud_functions"
export CLOUD_FUNCTION_NAME_RUN_BATCH='run_dragen_job'
export SOURCE_DIR_RUN_BATCH="${CLOUD_FUNCTIONS_DIR}/run_batch"  # Cloud Function Directory - relative (main.py)
export SOURCE_ENTRY_POINT_RUN_BATCH='run_job' # Entry point for Cloud Function
export RUNTIME='python310' # The only properly Supported for Runtime Environment
export INGRESS_SETTINGS=internal-and-gclb
export TRIGGER_FILE_NAME="START_PIPELINE"
export START_PIPELINE_FILE="${SOURCE_DIR_RUN_BATCH}/${TRIGGER_FILE_NAME}"

# Common Shared package
export ARTIFACTS_REPO="python-repo"
export COMMON_PACKAGE_NAME="commonek"
export COMMON_PACKAGE_VERSION="0.0.1"

# Cloud Function Get Status
export CLOUD_FUNCTION_NAME_GET_STATUS='get_status'
export SOURCE_DIR_GET_STATUS="${CLOUD_FUNCTIONS_DIR}/get_status"  # Cloud Function Directory - relative (main.py)
export SOURCE_ENTRY_POINT_GET_STATUS='get_status'
export PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE="job-dragen-task-state-change-topic"
export JOBS_INFO_PATH="gs://${OUTPUT_BUCKET_NAME}/jobs_created"

# Cloud Function Scheduler
export CLOUD_FUNCTION_NAME_SCHEDULER='job_scheduler'
export SOURCE_DIR_SCHEDULER="${CLOUD_FUNCTIONS_DIR}/scheduler"  # Cloud Function Directory - relative (main.py)
export SOURCE_ENTRY_POINT_SCHEDULER='get_job_update'
export TRIGGER_JOB_LIST_FILE_NAME="jobs.csv"
export TRIGGER_JOB_LIST_FILE="${ROOT_DIR}/tests/${TRIGGER_JOB_LIST_FILE_NAME}"
export JOBS_LIST_URI="gs://${INPUT_BUCKET_NAME}/scheduler/${TRIGGER_JOB_LIST_FILE_NAME}" #Copies the job execution schedule used by scheuler
export PUBSUB_TOPIC_BATCH_JOB_STATE_CHANGE="job-dragen-job-state-change-topic"

# TESTS
export TEST_RUN_DIR="gs://${INPUT_BUCKET_NAME}/test"

# BIGQUERY
export DATASET="dragen_illumina"
export TASK_STATUS_TABLE_ID="tasks_status"
export JOB_ARRAY_TABLE_ID="job_array"
export BIGQUERY_DB_TASKS="${DATASET}.${TASK_STATUS_TABLE_ID}"
export BIGQUERY_DB_JOB_ARRAY="${DATASET}.${JOB_ARRAY_TABLE_ID}"


# Terraform
export TF_VAR_project_id=${PROJECT_ID}
export TF_BUCKET_NAME="${PROJECT_ID}-tfstate"
export TF_BUCKET_LOCATION="us"
ADMIN_EMAIL=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
export ADMIN_EMAIL
export TF_VAR_admin_email=${ADMIN_EMAIL}
export TF_VAR_region=${GCLOUD_REGION}
export TF_VAR_vpc_network=${GCLOUD_NETWORK}
export TF_VAR_vpc_subnetwork=${GCLOUD_SUBNET}
export TF_VAR_config_bucket=${CONFIG_BUCKET_NAME}
export TF_VAR_trigger_bucket=${INPUT_BUCKET_NAME}
export TF_VAR_output_bucket=${OUTPUT_BUCKET_NAME}
export TF_VAR_data_bucket=${DATA_BUCKET_NAME}
export TF_VAR_tasks_status_table_id=${TASK_STATUS_TABLE_ID}
export TF_VAR_job_array_table_id=${JOB_ARRAY_TABLE_ID}
export TF_VAR_dataset_id=${DATASET}
export TF_VAR_pubsub_topic_batch_job_state_change=$PUBSUB_TOPIC_BATCH_JOB_STATE_CHANGE
export TF_VAR_pubsub_topic_batch_task_state_change=$PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE

export TF_VAR_job_service_account_name=${SA_JOB_NAME}
export TF_VAR_illumina_lic_server_secret_name=$ILLUMINA_LIC_SERVER_SECRET_NAME
export TF_VAR_illumina_lic_server_secret_data=$ILLUMINA_LICENSE
export TF_VAR_jarvice_api_key_secret_name=$JARVICE_API_KEY_SECRET_NAME
export TF_VAR_jarvice_api_key=$JXE_APIKEY
export TF_VAR_jarvice_api_username_secret_name=$JARVICE_API_USERNAME_SECRET_NAME
export TF_VAR_jarvice_api_username=$JXE_USERNAME

# SLACK
export SLACK_API_TOKEN_SECRET_NAME="slack-api-token"

echo "Using: "
echo "      PROJECT_ID=$PROJECT_ID"
echo "      INPUT_BUCKET_NAME=$INPUT_BUCKET_NAME"
echo "      OUTPUT_BUCKET_NAME=$OUTPUT_BUCKET_NAME"
echo "      JOB_SERVICE_ACCOUNT=$JOB_SERVICE_ACCOUNT"
echo "      DATA_BUCKET_NAME=$DATA_BUCKET_NAME"
echo "      CONFIG_BUCKET_NAME=$CONFIG_BUCKET_NAME"
echo "      TF_BUCKET_NAME=$TF_BUCKET_NAME"
