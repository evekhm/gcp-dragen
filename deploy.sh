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
printf="$DIR/utils/print"
gcloud config set project $PROJECT_ID

source "${DIR}"/SET

$printf "Deploying Cloud Function=[$CLOUD_FUNCTION_NAME_RUN_BATCH]..."
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
    --set-env-vars S3_SECRET=$S3_SECRET \
    --set-env-vars LICENSE_SECRET=$LICENSE_SECRET \
    --set-env-vars PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE=$PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE \
    --trigger-resource=gs://${INPUT_BUCKET_NAME} \
    --trigger-event=google.storage.object.finalize

gcloud functions deploy ${CLOUD_FUNCTION_NAME_GET_STATUS} \
    --region=$GCLOUD_REGION \
    --trigger-topic ${PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE} \
    --runtime $RUNTIME --source="${SOURCE_DIR_GET_STATUS}" \
    --entry-point=${SOURCE_ENTRY_POINT_RUN_BATCH} \
    --service-account=$JOB_SERVICE_ACCOUNT \
    --ingress-settings=${INGRESS_SETTINGS} \
    --set-env-vars GCLOUD_REGION=$GCLOUD_REGION \
    --set-env-vars JOBS_INFO=$JOBS_INFO \
    --set-env-vars BIGQUERY_DB=$BIGQUERY_DB \
    --set-env-vars PROJECT_ID=$PROJECT_ID

