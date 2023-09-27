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
printf="$DIR/../utils/print"

function setup_env_vars(){
    source "${DIR}/init_env_vars.sh" > /dev/null 2>&1
}

function generate_config_files(){
  bash -e "${DIR}/../utils/get_configs.sh"
}

function build_common_package(){
  bash "${DIR}/build_package.sh"
}

function delete_cloud_function(){
  exists=$(gcloud functions describe $NAME 2> /dev/null)
    if [ -n "$exists" ]; then
      printf "Deleting existing Cloud Function, to apply changes. Service will be unavailable during that time..."
      NAME=$1
      gen2=$(gcloud functions describe $NAME --format='value(environment)')
      if [ -n "$gen2" ]; then
        gen2=" --gen2"
        gcloud functions delete "$NAME" --region=$GCLOUD_REGION "$gen2"
      fi
    fi
}

function deploy_run_batch_cf(){
  $printf "Deploying Cloud Function=[$CLOUD_FUNCTION_NAME_RUN_BATCH]..."

  sed 's|__GCLOUD_REGION__|'"$GCLOUD_REGION"'|g;
      s|__PROJECT_ID__|'"$PROJECT_ID"'|g;
      ' "${SOURCE_DIR_RUN_BATCH}/requirements.sample.txt" > "${SOURCE_DIR_RUN_BATCH}/requirements.txt"
  #delete_cloud_function $CLOUD_FUNCTION_NAME_RUN_BATCH
  gcloud functions deploy $CLOUD_FUNCTION_NAME_RUN_BATCH \
      --region=$GCLOUD_REGION \
      --runtime $RUNTIME --source="${SOURCE_DIR_RUN_BATCH}" \
      --service-account=$JOB_SERVICE_ACCOUNT \
      --timeout=400 \
      --ingress-settings=${INGRESS_SETTINGS} \
      --set-env-vars GCLOUD_REGION=$GCLOUD_REGION \
      --set-env-vars JOB_NAME_SHORT=$JOB_NAME_SHORT \
      --set-env-vars GCLOUD_NETWORK=$GCLOUD_NETWORK \
      --set-env-vars GCLOUD_SUBNET=$GCLOUD_SUBNET \
      --set-env-vars JOB_SERVICE_ACCOUNT=$JOB_SERVICE_ACCOUNT \
      --set-env-vars GCLOUD_MACHINE=$GCLOUD_MACHINE \
      --set-env-vars TRIGGER_FILE_NAME=$TRIGGER_FILE_NAME \
      --set-env-vars S3_ACCESS_KEY_SECRET_NAME=$S3_ACCESS_KEY_SECRET_NAME \
      --set-env-vars S3_SECRET_KEY_SECRET_NAME=$S3_SECRET_KEY_SECRET_NAME \
      --set-env-vars ILLUMINA_LIC_SERVER_SECRET_NAME=$ILLUMINA_LIC_SERVER_SECRET_NAME \
      --set-env-vars JARVICE_API_KEY_SECRET_NAME=$JARVICE_API_KEY_SECRET_NAME \
      --set-env-vars JARVICE_API_USERNAME_SECRET_NAME=$JARVICE_API_USERNAME_SECRET_NAME \
      --set-env-vars JOBS_INFO_PATH=$JOBS_INFO_PATH \
      --set-env-vars BIGQUERY_DB_TASKS=$BIGQUERY_DB_TASKS \
      --set-env-vars PROJECT_ID=$PROJECT_ID \
      --set-env-vars JOBS_LIST_URI=$JOBS_LIST_URI \
      --set-env-vars PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE=${PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE} \
      --set-env-vars PUBSUB_TOPIC_BATCH_JOB_STATE_CHANGE=${PUBSUB_TOPIC_BATCH_JOB_STATE_CHANGE} \
      --trigger-resource=gs://"${INPUT_BUCKET_NAME}" \
      --trigger-event=google.storage.object.finalize --docker-registry=artifact-registry
}

function deploy_get_status_cf(){
  sed 's|__GCLOUD_REGION__|'"$GCLOUD_REGION"'|g;
      s|__PROJECT_ID__|'"$PROJECT_ID"'|g;
      ' "${SOURCE_DIR_GET_STATUS}/requirements.sample.txt" > "${SOURCE_DIR_GET_STATUS}/requirements.txt"
  $printf "Deploying Cloud Function=[$CLOUD_FUNCTION_NAME_GET_STATUS]..."
  gcloud functions deploy ${CLOUD_FUNCTION_NAME_GET_STATUS} \
      --region=$GCLOUD_REGION \
      --trigger-topic ${PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE} \
      --runtime $RUNTIME --source="${SOURCE_DIR_GET_STATUS}" \
      --entry-point=${SOURCE_ENTRY_POINT_GET_STATUS} \
      --service-account=$JOB_SERVICE_ACCOUNT \
      --ingress-settings=${INGRESS_SETTINGS} \
      --set-env-vars JOBS_INFO_PATH=$JOBS_INFO_PATH \
      --set-env-vars BIGQUERY_DB_TASKS=$BIGQUERY_DB_TASKS \
      --set-env-vars PROJECT_ID=$PROJECT_ID --docker-registry=artifact-registry
}

function deploy_scheduler_cf(){
  sed 's|__GCLOUD_REGION__|'"$GCLOUD_REGION"'|g;
      s|__PROJECT_ID__|'"$PROJECT_ID"'|g;
      ' "${SOURCE_DIR_SCHEDULER}/requirements.sample.txt" > "${SOURCE_DIR_SCHEDULER}/requirements.txt"
  $printf "Deploying Cloud Function=[$CLOUD_FUNCTION_NAME_SCHEDULER]..."
  gcloud functions deploy ${CLOUD_FUNCTION_NAME_SCHEDULER} \
      --region=$GCLOUD_REGION \
      --trigger-topic ${PUBSUB_TOPIC_BATCH_JOB_STATE_CHANGE} \
      --runtime $RUNTIME --source="${SOURCE_DIR_SCHEDULER}" \
      --entry-point=${SOURCE_ENTRY_POINT_SCHEDULER} \
      --set-env-vars TRIGGER_FILE_NAME=$TRIGGER_FILE_NAME \
      --service-account=$JOB_SERVICE_ACCOUNT \
      --ingress-settings=${INGRESS_SETTINGS} \
      --set-env-vars JOBS_LIST_URI=$JOBS_LIST_URI \
      --set-env-vars JOBS_INFO_PATH=$JOBS_INFO_PATH \
      --set-env-vars PROJECT_ID=$PROJECT_ID --docker-registry=artifact-registry
}

setup_env_vars

generate_config_files

build_common_package

deploy_run_batch_cf

deploy_get_status_cf

deploy_scheduler_cf

$printf "Success! Infrastructure deployed and ready!"

