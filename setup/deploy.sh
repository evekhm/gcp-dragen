#!/bin/bash
gcloud config set project $PROJECT_ID

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
  source "${DIR}"/../SET


echo "Deploying Cloud Function=[$SOURCE_ENTRY_POINT]..."
gcloud functions deploy $CLOUD_FUNCTION_NAME \
    --region=$GCLOUD_REGION \
    --runtime $RUNTIME --source="${SOURCE_DIR}" \
    --entry-point=$SOURCE_ENTRY_POINT \
    --service-account=$JOB_SERVICE_ACCOUNT \
    --timeout=400 \
    --ingress-settings=${INGRESS_SETTINGS} \
    --set-env-vars REGION=$GCLOUD_REGION \
    --set-env-vars JOB_NAME=$JOB_NAME_SHORT \
    --set-env-vars NETWORK=$GCLOUD_NETWORK \
    --set-env-vars SUBNET=$GCLOUD_SUBNET \
    --set-env-vars SERVICE_ACCOUNT_EMAIL=$JOB_SERVICE_ACCOUNT \
    --set-env-vars MACHINE=$GCLOUD_MACHINE \
    --trigger-resource=gs://${INPUT_BUCKET} \
    --trigger-event=google.storage.object.finalize





