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
LOG="$DIR/setup.log"
filename=$(basename $0)
timestamp=$(date +"%m-%d-%Y_%H:%M:%S")
$printf "$timestamp - Running $filename ...  ( DISABLE_POLICY=$DISABLE_POLICY)" | tee "$LOG"

if [[ -z "${PROJECT_ID}" ]]; then
  echo PROJECT_ID variable is not set. | tee -a "$LOG"
  exit
fi

if [[ -n "${DISABLE_POLICY}" ]]; then
    $printf "The script will try to automatically enable all required Org policies since env variable is set: DISABLE_POLICY=$DISABLE_POLICY" | tee -a "$LOG"
else
    $printf "The script will skip automatic setting of the required Org policies. Please verify manually that all policies are set as required (Check README.md) " | tee -a "$LOG"
    $printf "If you have the Org policy admin role, you could try enabling policies automatically by setting environment variable: DISABLE_POLICY=on" | tee -a "$LOG"
fi

gcloud config set project $PROJECT_ID

source "${DIR}"/SET

### Functions
function create_secret(){
  secret_name=$1
  secret_value=$2
  exists=$(gcloud secrets describe "${secret_name}" 2> /dev/null)
  if [ -z "$exists" ]; then
    $printf "Creating $secret_name secret..."  | tee -a "$LOG"
    printf "$secret_value" | gcloud secrets create "$secret_name" --replication-policy="user-managed" --project $PROJECT_ID  --data-file=-  --locations=$GCLOUD_REGION
  fi
}

function create_pubsub_topic(){
  TOPIC_ID=$1

  if gcloud pubsub topics list 2>/dev/null | grep "$TOPIC_ID"; then
    $printf "Topic [$TOPIC_ID] already exists - skipping step" INFO
  else
    $printf "Creating topic [$TOPIC_ID]..." INFO
    gcloud pubsub topics create "$TOPIC_ID"
  fi

  gcloud pubsub topics add-iam-policy-binding "$TOPIC_ID" \
      --member="serviceAccount:$JOB_SERVICE_ACCOUNT"\
      --role="roles/pubsub.editor" > /dev/null 2>&1
  gcloud pubsub topics add-iam-policy-binding "$TOPIC_ID" \
      --member="serviceAccount:$JOB_SERVICE_ACCOUNT"\
      --role="roles/pubsub.publisher" > /dev/null 2>&1
}

function create_bucket(){
  bucket_name=$1
  gsutil ls "gs://${bucket_name}" > /dev/null 2>&1
  RETURN=$?
  if [[ $RETURN -gt 0 ]]; then
      $printf "Creating GCS Bucket gs://${bucket_name}..."   INFO  | tee -a "$LOG"
      gsutil mb -p "${PROJECT_ID}" gs://"$bucket_name"
  fi
}

function create_bucket_regional(){
  bucket_name=$1
  gsutil ls "gs://${bucket_name}" > /dev/null 2>&1
  RETURN=$?
  if [[ $RETURN -gt 0 ]]; then
      $printf "Creating GCS regional=${GCLOUD_REGION} Bucket gs://${bucket_name}..."   INFO  | tee -a "$LOG"
      gsutil mb -p "${PROJECT_ID}" -l "${GCLOUD_REGION}"  gs://"$bucket_name"
  fi
}

function create_bq_dt(){
  $printf "Creating BigQuery Dataset=${DATASET} and Table=${TASK_STATUS_TABLE_ID} ..."  | tee -a "$LOG"
  if bq --location="${GCLOUD_REGION}" ls 2> /dev/null| grep  "${DATASET}"; then
    $printf "Dataset already exists [${DATASET}] - skipping step" INFO  | tee -a "$LOG"
  else
    bq --location="${GCLOUD_REGION}" mk --dataset "${DATASET}" > /dev/null 2>&1
  fi

  if bq --location="${GCLOUD_REGION}" ls "${DATASET}" 2> /dev/null | grep  "${TASK_STATUS_TABLE_ID}"; then
    :
  else
    bq mk  --schema="${DIR}/setup/bq_task_status_schema.json" --table "${DATASET}"."${TASK_STATUS_TABLE_ID}"  2> /dev/null
  fi
  bq add-iam-policy-binding \
     --member="serviceAccount:$JOB_SERVICE_ACCOUNT"\
     --role="roles/bigquery.dataEditor" \
     "${PROJECT_ID}:${DATASET}.${TASK_STATUS_TABLE_ID}" > /dev/null 2>&1
 }


function disable_org_policy_constraints(){
  $printf "Setting Policy Constraints..."  | tee -a "$LOG"
  gcloud org-policies reset constraints/iam.disableServiceAccountCreation --project=$PROJECT_ID
  gcloud org-policies reset constraints/iam.disableServiceAccountKeyCreation --project=$PROJECT_ID
  gcloud org-policies reset constraints/compute.vmExternalIpAccess --project=$PROJECT_ID
  gcloud org-policies reset constraints/compute.requireShieldedVm --project=$PROJECT_ID
  gcloud org-policies reset constraints/storage.restrictAuthTypes --project=$PROJECT_ID

  echo "Allow up to 30 seconds to propagate the policy changes..."
  sleep 30
  echo "Policy Changes done"
  # Otherwise fails on PreconditionException: 412 Request violates constraint 'constraints/iam.disableServiceAccountKeyCreation'

  ready=$(gcloud org-policies describe constraints/iam.disableServiceAccountKeyCreation --project=$PROJECT_ID 2>/dev/null)
  while [ -z "$ready" ]; do
    ready=$(gcloud org-policies describe constraints/iam.disableServiceAccountKeyCreation --project=$PROJECT_ID 2>/dev/null)
    sleep 5;
  done

  gcloud resource-manager org-policies describe    compute.trustedImageProjects --project=$PROJECT_ID    --effective > policy.yaml
  echo "  - projects/illumina-dragen" >> policy.yaml
  echo "  - projects/$GCLOUD_IMAGE_PROJECT" >> policy.yaml
  echo "  - projects/$GCLOUD_BATCH_IMAGE_PROJECT" >> policy.yaml
  gcloud resource-manager org-policies set-policy \
     policy.yaml --project=$PROJECT_ID
  rm  policy.yaml

  $printf "Finished with Org policy Update"  INFO | tee -a "$LOG"
}

function add_role_binding_to_service_account(){
  SA_EMAIL=$1
  ROLE=$2
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
          --member="serviceAccount:${SA_EMAIL}" \
          --role="$ROLE" > /dev/null 2>&1
}

function setup_secrets(){
  exists=$(gcloud secrets describe ${LICENSE_SECRET} 2> /dev/null)
  if [ -z "$exists" ]; then
    if [[ -z "${ILLUMINA_LICENSE}" ]]; then
      echo ILLUMINA_LICENSE variable is not set. | tee -a "$LOG"
      exit
    fi

    if [[ -z "${JXE_APIKEY}" ]]; then
      echo JXE_APIKEY variable is not set. | tee -a "$LOG"
      exit
    fi

    if [[ -z "${JXE_USERNAME}" ]]; then
      echo JXE_USERNAME variable is not set. | tee -a "$LOG"
      exit
    fi
    $printf "Creating $LICENSE_SECRET secret..."  | tee -a "$LOG"
    [ ! -d "$DIR/tmp" ] && mkdir "$DIR/tmp"
    echo "{\"illumina_license\": \"${ILLUMINA_LICENSE}\",  \"jxe_apikey\": \"${JXE_APIKEY}\" , \"jxe_username\" : \"${JXE_USERNAME}\" }" > tmp/licsecret.json
    gcloud secrets create $LICENSE_SECRET --replication-policy="automatic" --project=$PROJECT_ID | tee -a "$LOG"
    gcloud secrets versions add $LICENSE_SECRET --data-file="tmp/licsecret.json" | tee -a "$LOG"
    rm -rf tmp/licsecret.json # delete temp file
  fi


  LICENSE_SECRET_KEY=$(gcloud secrets versions access latest --secret="$LICENSE_SECRET" --project=$PROJECT_ID | jq ".illumina_license" | tr -d '"')
  if [ -z "$LICENSE_SECRET_KEY" ] ; then
    echo "$LICENSE_SECRET was not created properly, missing illumina_license" | tee -a "$LOG"
    echo "Try running following command to debug:" | tee -a "$LOG"
    echo "  gcloud secrets versions access latest --secret=$LICENSE_SECRET --project=$PROJECT_ID " | tee -a "$LOG"
    echo "  gcloud secrets versions list  $LICENSE_SECRET --project=$PROJECT_ID " | tee -a "$LOG"
    exit
  fi

  # For the New batch Flow (secrets required separately)
  create_secret "${ILLUMINA_LIC_SERVER_SECRET_NAME}" "https://${LICENSE_SECRET_KEY}@license.edicogenome.com"

  JARVICE_API_KEY=$(gcloud secrets versions access latest --secret="$LICENSE_SECRET" --project=$PROJECT_ID | jq ".jxe_apikey" | tr -d '"')
  if [ -z "$JARVICE_API_KEY" ] ; then
    echo "$LICENSE_SECRET was not created properly, missing jxe_apikey" | tee -a "$LOG"
    echo "Try running following command to debug:" | tee -a "$LOG"
    echo "  gcloud secrets versions access latest --secret=$LICENSE_SECRET --project=$PROJECT_ID " | tee -a "$LOG"
    echo "  gcloud secrets versions list  $LICENSE_SECRET --project=$PROJECT_ID " | tee -a "$LOG"
    exit
  fi
  create_secret "${JARVICE_API_KEY_SECRET_NAME}" "${JARVICE_API_KEY}"

  JARVICE_API_USERNAME=$(gcloud secrets versions access latest --secret="$LICENSE_SECRET" --project=$PROJECT_ID | jq ".jxe_username" | tr -d '"')
  if [ -z "$JARVICE_API_USERNAME" ] ; then
    echo "$LICENSE_SECRET was not created properly, missing jxe_apikey" | tee -a "$LOG"
    echo "Try running following command to debug:" | tee -a "$LOG"
    echo "  gcloud secrets versions access latest --secret=$LICENSE_SECRET --project=$PROJECT_ID " | tee -a "$LOG"
    echo "  gcloud secrets versions list  $LICENSE_SECRET --project=$PROJECT_ID " | tee -a "$LOG"
    exit
  fi
  create_secret "${JARVICE_API_USERNAME_SECRET_NAME}" "${JARVICE_API_USERNAME}"

  $printf "Verified $LICENSE_SECRET secret - Success!" | tee -a "$LOG"
}

function setup_network(){
  network=$(gcloud compute networks list --filter="name=(\"$GCLOUD_NETWORK\" )" --format='get(NAME)' 2>/dev/null)
  if [ -z "$network" ]; then
    $printf "Creating Network [$GCLOUD_NETWORK] ..."  | tee -a "$LOG"
    gcloud compute networks create "$GCLOUD_NETWORK" --project="$PROJECT_ID" --subnet-mode=custom \
    --mtu=1460 --bgp-routing-mode=regional

    ## Use network name as subnet name (from Instructions)
    gcloud compute networks subnets create "$GCLOUD_SUBNET" --project="$PROJECT_ID" \
    --range=10.0.0.0/24 --stack-type=IPV4_ONLY --network="$GCLOUD_NETWORK" --region=us-central1

  fi

  # FW rule for Regional Extension to access The JARVICE API hosted by the Regional Extension
  fwrule_exists=$(gcloud compute --project="$PROJECT_ID" firewall-rules describe jarvice-api 2>/dev/null)
  if [ -z "$fwrule_exists" ]; then
    gcloud compute --project="$PROJECT_ID" firewall-rules create jarvice-api \
    --direction=EGRESS --priority=1000 --network="$GCLOUD_NETWORK" --action=ALLOW \
    --rules=tcp:443 --destination-ranges=35.184.114.150
  fi
}

function setup_hmac_keys(){
  ##### HMAC Secret cannot be retrieved once created
  #### Check if secret already exists => Skip Creation of HMAC key
  $printf "Verifying Secrets and HMAC keys..."  | tee -a "$LOG"
  [ ! -d "$DIR/tmp" ] && mkdir "$DIR/tmp"
  SA_EXISTS=$(gcloud iam service-accounts list --filter="${SA_NAME_STORAGE}" | wc -l)
  if [ $SA_EXISTS = "0" ]; then
    $printf "Creating service account ${SA_NAME_STORAGE}..."  | tee -a "$LOG"
    gcloud iam service-accounts create $SA_NAME_STORAGE \
            --description="Storage Admin" \
            --display-name="storage-admin" > /dev/null 2>&1
    gcloud projects add-iam-policy-binding $PROJECT_ID \
            --member="serviceAccount:${SA_EMAIL_STORAGE}" \
            --role="roles/storage.admin" > /dev/null 2>&1
  fi
  exists=$(gcloud secrets describe ${S3_SECRET} 2> /dev/null)
  if [ -z "$exists" ]; then
    $printf "Creating HMAC keys..."  | tee -a "$LOG"
    gsutil hmac create "$SA_EMAIL_STORAGE" > tmp/hmackey.txt
    access_key=`cat  tmp/hmackey.txt  | awk  -F: '{print $2}' | xargs | awk '{print $1}'`
    access_secret=`cat  tmp/hmackey.txt  | awk  -F: '{print $2}' | xargs | awk '{print $2}'`
    echo "{\"access_key\": \"${access_key}\",  \"access_secret\": \"${access_secret}\" , \"endpoint\" : \"https://storage.googleapis.com\" }" > tmp/hmacsecret.json

    $printf "Creating ${S3_SECRET} secret..."  | tee -a "$LOG"
    gcloud secrets create $S3_SECRET --replication-policy="automatic" --project=$PROJECT_ID | tee -a "$LOG"

    gcloud secrets versions add $S3_SECRET --data-file="tmp/hmacsecret.json" | tee -a "$LOG"
    rm -rf tmp/hmacsecret.json tmp/hmackey.txt # delete temp file
  fi
  S3_ACCESS_KEY=$(gcloud secrets versions access latest --secret="$S3_SECRET" --project=$PROJECT_ID | jq ".access_key" | tr -d '"')
  S3_SECRET_KEY=$(gcloud secrets versions access latest --secret="$S3_SECRET" --project=$PROJECT_ID | jq ".access_secret" | tr -d '"')
  if [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ] ; then
    echo "$S3_SECRET was not created properly (HMAC key count limit reached?)"
    echo "Try running following command to debug:"
    echo "  gcloud secrets versions access latest --secret=$S3_SECRET --project=$PROJECT_ID "
    echo " When HMAC Key Limit is reached, old HMAC Key needs to be de-activated and deleted, before new one can be re-created"
    echo "  gsutil hmac list -u $SA_EMAIL_STORAGE"
    exit
  else
    $printf  "Verified $S3_SECRET for HMAC keys - Success!" | tee -a "$LOG"
  fi

  # For the New batch Flow
  create_secret "${S3_ACCESS_KEY_SECRET_NAME}" "${S3_ACCESS_KEY}"
  create_secret "${S3_SECRET_KEY_SECRET_NAME}" "${S3_SECRET_KEY}"

}

function setup_job_service_account(){
  SA_EXISTS=$(gcloud iam service-accounts list --filter="${SA_JOB_NAME}" | wc -l)
  if [ $SA_EXISTS = "0" ]; then
    $printf "Creating ${SA_JOB_NAME} Service Account to execute Batch Job"  | tee -a "$LOG"
    gcloud iam service-accounts create $SA_JOB_NAME \
            --description="Service Account to execute batch Job" \
            --display-name=$SA_JOB_NAME | tee -a "$LOG"
  fi

  $printf  "Setting IAM policies ... " | tee -a "$LOG"
  add_role_binding_to_service_account "${JOB_SERVICE_ACCOUNT}" "roles/compute.serviceAgent"
  add_role_binding_to_service_account "${JOB_SERVICE_ACCOUNT}" "roles/compute.admin"

  # permissions  to create a job (https://cloud.google.com/batch/docs/create-run-job-custom-service-account)
  add_role_binding_to_service_account "${JOB_SERVICE_ACCOUNT}" "roles/iam.serviceAccountUser"

  add_role_binding_to_service_account "${JOB_SERVICE_ACCOUNT}" "roles/batch.jobsEditor"
  add_role_binding_to_service_account "${JOB_SERVICE_ACCOUNT}" "roles/iam.serviceAccountViewer"

  add_role_binding_to_service_account "${JOB_SERVICE_ACCOUNT}" "roles/logging.logWriter" # For Log Monitoring
  add_role_binding_to_service_account "${JOB_SERVICE_ACCOUNT}" "roles/batch.agentReporter" # For Batch Job
  add_role_binding_to_service_account "${JOB_SERVICE_ACCOUNT}" "roles/secretmanager.viewer" # To access Secret
  add_role_binding_to_service_account "${JOB_SERVICE_ACCOUNT}" "roles/secretmanager.secretAccessor" # To access Secret
  add_role_binding_to_service_account "${JOB_SERVICE_ACCOUNT}" "roles/artifactregistry.reader" # To access AR
  add_role_binding_to_service_account "${JOB_SERVICE_ACCOUNT}" "roles/artifactregistry.writer" # To write Python Package to AR
  add_role_binding_to_service_account "${JOB_SERVICE_ACCOUNT}" "roles/logging.admin" # To Get Logging Analysis (Could be better scoped)
  add_role_binding_to_service_account "${JOB_SERVICE_ACCOUNT}" "roles/storage.admin"  # Otherwise getting 403 GET ERROR for config.json
  add_role_binding_to_service_account "${JOB_SERVICE_ACCOUNT}" "roles/bigquery.dataEditor"  # For BigQuery access (Could be narrowed down to the dataset)

  # To load config.json
  #gcloud storage buckets add-iam-policy-binding  gs://"${INPUT_BUCKET_NAME}" --member="serviceAccount:${JOB_SERVICE_ACCOUNT}" --role="roles/storage.objectViewer"  2>&1
  #gcloud storage buckets add-iam-policy-binding  gs://"${OUTPUT_BUCKET_NAME}" --member="serviceAccount:${JOB_SERVICE_ACCOUNT}" --role="roles/storage.objectViewer"  2>&1
}
### START Setting Up Infrastructure

# Disable org Policies (optional)
if [ -n "$DISABLE_POLICY" ]; then
  gcloud services enable orgpolicy.googleapis.com #To avoid Error for concurrent policy changes.
  enabled=$(gcloud services list --enabled | grep orgpolicy)
  while [ -z "$enabled" ]; do
    enabled=$(gcloud services list --enabled | grep orgpolicy)
    sleep 5;
  done

  disable_org_policy_constraints
fi

# Enable APIs
$printf "Enabling Required APIs..."  | tee -a "$LOG"
  APIS="compute.googleapis.com \
    pubsub.googleapis.com \
    batch.googleapis.com \
    cloudresourcemanager.googleapis.com \
    secretmanager.googleapis.com \
    logging.googleapis.com \
    storage.googleapis.com \
    cloudfunctions.googleapis.com \
    cloudbuild.googleapis.com \
    iam.googleapis.com \
    bigquery.googleapis.com \
    cloudresourcemanager.googleapis.com"


# gcloud services list --enabled|grep -v NAME|wc -l
gcloud services enable $APIS
enabled=$(gcloud services list --enabled | grep compute)
while [ -z "$enabled" ]; do
  enabled=$(gcloud services list --enabled | grep compute)
  sleep 5;
done

setup_secrets

setup_network

$printf "Setting up Cloud Storage"  | tee -a "$LOG"
create_bucket "${INPUT_BUCKET_NAME}"
create_bucket "${DATA_BUCKET_NAME}"
create_bucket "${CONFIG_BUCKET_NAME}"
create_bucket "${OUTPUT_BUCKET_NAME}"
gsutil versioning set on "gs://${CONFIG_BUCKET_NAME}"

setup_hmac_keys

setup_job_service_account

create_bq_dt

# Before creating a trigger for direct events from Cloud Storage, grant the Pub/Sub Publisher role (roles/pubsub.publisher)
# to the Cloud Storage service agent, a Google-managed service account:
SERVICE_ACCOUNT="$(gsutil kms serviceaccount -p $PROJECT_ID)"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role='roles/pubsub.publisher' > /dev/null 2>&1
create_pubsub_topic "$PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE"
create_pubsub_topic "$PUBSUB_TOPIC_BATCH_JOB_STATE_CHANGE"


bash "${DIR}/setup/build_package.sh" | tee -a "$LOG"

bash -e "${DIR}/utils/get_configs.sh" | tee -a "$LOG"

bash -e "${DIR}"/deploy.sh | tee -a "$LOG"


# preparing for test data
gsutil cp "${DIR}/tests/jobs_created/*" "$JOBS_INFO_PATH/"

$printf "Success! Infrastructure deployed and ready!"  | tee -a "$LOG"

echo " > Start the pipeline: "  | tee -a "$LOG"
echo "Drop empty file named START_PIPELINE inside gs://${INPUT_BUCKET_NAME}/<folder_with_batch_config> "  | tee -a "$LOG"


timestamp=$(date +"%m-%d-%Y_%H:%M:%S")
echo "$timestamp Finished. Saved Log into $LOG"  | tee -a "$LOG"