#!/bin/bash
gcloud config set project $PROJECT_ID

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
  source "${DIR}"/SET

echo "Deploying Cloud Function=[$SOURCE_ENTRY_POINT]..."
gcloud functions deploy $CLOUD_FUNCTION_NAME \
    --region=$GCLOUD_REGION \
    --runtime $RUNTIME --source="${SOURCE_DIR}" \
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
    --set-env-vars LICENCE_SECRET=$LICENCE_SECRET \
    --trigger-resource=gs://${INPUT_BUCKET} \
    --trigger-event=google.storage.object.finalize





