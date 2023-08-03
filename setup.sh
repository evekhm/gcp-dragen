#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
printf="$DIR/utils/print"
LOG="$DIR/setup.log"
filename=$(basename $0)
timestamp=$(date +"%m-%d-%Y_%H:%M:%S")
$printf "$timestamp - Running $filename ... " | tee "$LOG"

if [[ -z "${PROJECT_ID}" ]]; then
  echo PROJECT_ID variable is not set. | tee -a "$LOG"
  exit
fi

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

gcloud config set project $PROJECT_ID

source "${DIR}"/SET

function create_bucket(){
  bucket_name=$1
  gsutil ls "gs://${bucket_name}" 2> /dev/null
  RETURN=$?
  if [[ $RETURN -gt 0 ]]; then
      $printf "Creating GCS Bucket gs://${bucket_name}..."  | tee -a "$LOG"
      gsutil mb gs://$bucket_name
  fi
}
# gcloud services list --enabled|grep -v NAME|wc -l

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
    cloudresourcemanager.googleapis.com"

gcloud services enable orgpolicy.googleapis.com #To avoid Error for concurrent policy changes.

enabled=$(gcloud services list --enabled | grep orgpolicy)
while [ -z "$enabled" ]; do
  enabled=$(gcloud services list --enabled | grep orgpolicy)
  sleep 5;
done


# gcloud services list --enabled|grep -v NAME|wc -l
gcloud services enable $APIS

enabled=$(gcloud services list --enabled | grep compute)
while [ -z "$enabled" ]; do
  enabled=$(gcloud services list --enabled | grep compute)
  sleep 5;
done

$printf "Setting Policy Constraints..."  | tee -a "$LOG"
gcloud org-policies reset constraints/iam.disableServiceAccountCreation --project=$PROJECT_ID
gcloud org-policies reset constraints/iam.disableServiceAccountKeyCreation --project=$PROJECT_ID
gcloud org-policies reset constraints/compute.vmExternalIpAccess --project=$PROJECT_ID
gcloud org-policies reset constraints/compute.requireShieldedVm --project=$PROJECT_ID
gcloud org-policies reset constraints/storage.restrictAuthTypes --project=$PROJECT_ID

echo "Allow upto 30 seconds to Propagate the policy changes"
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

network=$(gcloud compute networks list --filter="name=(\"$GCLOUD_NETWORK\" )" --format='get(NAME)' 2>/dev/null)
if [ -z "$network" ]; then
  $printf "Creating Network $GCLOUD_NETWORK ..."  | tee -a "$LOG"
  gcloud compute networks create "$GCLOUD_NETWORK" --project="$PROJECT_ID" --subnet-mode=custom \
  --mtu=1460 --bgp-routing-mode=regional

  ## Use network name as subnet name (from Instructions)
  gcloud compute networks subnets create "$GCLOUD_SUBNET" --project="$PROJECT_ID" \
  --range=10.0.0.0/24 --stack-type=IPV4_ONLY --network="$GCLOUD_NETWORK" --region=us-central1

  gcloud compute --project="$PROJECT_ID" firewall-rules create ingress-ssh \
  --direction=INGRESS --priority=1000 --network="$GCLOUD_NETWORK" --action=ALLOW \
  --rules=tcp:22 --source-ranges=0.0.0.0/0
fi

create_bucket "${INPUT_BUCKET_NAME}"
create_bucket "${OUTPUT_BUCKET_NAME}"

SA_EXISTS=$(gcloud iam service-accounts list --filter="${SA_NAME_STORAGE}" | wc -l)
if [ $SA_EXISTS = "0" ]; then
  $printf "Creating service account ${SA_NAME_STORAGE}..."  | tee -a "$LOG"
  gcloud iam service-accounts create $SA_NAME_STORAGE \
          --description="Storage Admin" \
          --display-name="storage-admin"
  gcloud projects add-iam-policy-binding $PROJECT_ID \
          --member="serviceAccount:${SA_EMAIL_STORAGE}" \
          --role="roles/storage.admin"
fi

[ ! -d "$DIR/tmp" ] && mkdir "$DIR/tmp"

$printf "Creating HMAC keys..."  | tee -a "$LOG"
gsutil hmac create "$SA_EMAIL_STORAGE" > tmp/hmackey.txt
access_key=`cat  tmp/hmackey.txt  | awk  -F: '{print $2}' | xargs | awk '{print $1}'`
access_secret=`cat  tmp/hmackey.txt  | awk  -F: '{print $2}' | xargs | awk '{print $2}'`
echo "{\"access_key\": \"${access_key}\",  \"access_secret\": \"${access_secret}\" , \"endpoint\" : \"https://storage.googleapis.com\" }" > tmp/hmacsecret.json

exists=$(gcloud secrets describe ${S3_SECRET} 2> /dev/null)
if [ -z "$exists" ]; then
  $printf "Creating ${S3_SECRET} secret..."  | tee -a "$LOG"
  gcloud secrets create $S3_SECRET --replication-policy="automatic" --project=$PROJECT_ID | tee -a "$LOG"
fi
gcloud secrets versions add $S3_SECRET --data-file="tmp/hmacsecret.json" | tee -a "$LOG"
rm -rf tmp/hmacsecret.json tmp/hmackey.txt # delete temp file

S3_ACCESS_KEY=$(gcloud secrets versions access latest --secret="$S3_SECRET" --project=$PROJECT_ID | jq ".access_key" | tr -d '"')
S3_SECRET_KEY=$(gcloud secrets versions access latest --secret="$S3_SECRET" --project=$PROJECT_ID | jq ".access_secret" | tr -d '"')
if [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ] ; then
  echo "$S3_SECRET was not created properly"
  echo "Try running following command to debug:"
  echo "  gcloud secrets versions access latest --secret=$S3_SECRET --project=$PROJECT_ID "
  exit
else
  echo "Successfully created $S3_SECRET secret."
fi

echo "{\"illumina_license\": \"${ILLUMINA_LICENSE}\",  \"jxe_apikey\": \"${JXE_APIKEY}\" , \"jxe_username\" : \"${JXE_USERNAME}\" }" > tmp/licsecret.json
exists=$(gcloud secrets describe ${LICENSE_SECRET} 2> /dev/null)
if [ -z "$exists" ]; then
  $printf "Creating $LICENSE_SECRET secret..."  | tee -a "$LOG"
  gcloud secrets create $LICENSE_SECRET --replication-policy="automatic" --project=$PROJECT_ID | tee -a "$LOG"
fi
gcloud secrets versions add $LICENSE_SECRET --data-file="tmp/licsecret.json" | tee -a "$LOG"
rm -rf tmp/licsecret.json # delete temp file

LICENSE_SECRET_KEY=$(gcloud secrets versions access latest --secret="$LICENSE_SECRET" --project=$PROJECT_ID | jq ".illumina_license" | tr -d '"')
if [ -z "$LICENSE_SECRET_KEY" ] ; then
  echo "$LICENSE_SECRET_KEY was not created properly" | tee -a "$LOG"
  echo "Try running following command to debug:" | tee -a "$LOG"
  echo "  gcloud secrets versions access latest --secret=$LICENSE_SECRET_KEY --project=$PROJECT_ID " | tee -a "$LOG"
  exit
else
  $printf "Successfully created $LICENSE_SECRET secret." | tee -a "$LOG"
fi
# terraform
#```shell
## Create a new service account
#resource "google_service_account" "service_account" {
#  account_id = "my-svc-acc"
#}
#
## Create the HMAC key for the associated service account
#resource "google_storage_hmac_key" "key" {
#  service_account_email = google_service_account.service_account.email
#}
#```

SA_EXISTS=$(gcloud iam service-accounts list --filter="${SA_JOB_NAME}" | wc -l)
if [ $SA_EXISTS = "0" ]; then
  $printf "Creating ${SA_JOB_NAME} Service Account to execute Batch Job"  | tee -a "$LOG"
  gcloud iam service-accounts create $SA_JOB_NAME \
          --description="Service Account to execute batch Job" \
          --display-name=$SA_JOB_NAME | tee -a "$LOG"
fi

# TODO Fine Grain Create Role
# # Create new Role
  ##compute.instances.create
  ##compute.instances.get
gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${JOB_SERVICE_ACCOUNT}" \
        --role="roles/compute.serviceAgent"
gcloud projects add-iam-policy-binding $PROJECT_ID \
         --member="serviceAccount:${JOB_SERVICE_ACCOUNT}" \
         --role="roles/compute.admin"

# permissions  to create a job (https://cloud.google.com/batch/docs/create-run-job-custom-service-account)
gcloud projects add-iam-policy-binding $PROJECT_ID \
         --member="serviceAccount:${JOB_SERVICE_ACCOUNT}" \
         --role="roles/iam.serviceAccountUser"
gcloud projects add-iam-policy-binding $PROJECT_ID \
         --member="serviceAccount:${JOB_SERVICE_ACCOUNT}" \
         --role="roles/batch.jobsEditor"
gcloud projects add-iam-policy-binding $PROJECT_ID \
         --member="serviceAccount:${JOB_SERVICE_ACCOUNT}" \
         --role="roles/iam.serviceAccountViewer"

# For Log Monitoring
gcloud projects add-iam-policy-binding $PROJECT_ID \
         --member="serviceAccount:${JOB_SERVICE_ACCOUNT}" \
         --role="roles/logging.logWriter"

# For Batch Job
gcloud projects add-iam-policy-binding $PROJECT_ID \
         --member="serviceAccount:${JOB_SERVICE_ACCOUNT}" \
         --role="roles/batch.agentReporter"

# To access Secret
gcloud projects add-iam-policy-binding $PROJECT_ID \
         --member="serviceAccount:${JOB_SERVICE_ACCOUNT}" \
         --role="roles/secretmanager.viewer"

# To access Secret ((secretmanager.versions.access))
gcloud projects add-iam-policy-binding $PROJECT_ID \
         --member="serviceAccount:${JOB_SERVICE_ACCOUNT}" \
         --role="roles/secretmanager.secretAccessor"

# To load config.json
#gcloud storage buckets add-iam-policy-binding  gs://"${INPUT_BUCKET_NAME}" --member="serviceAccount:${JOB_SERVICE_ACCOUNT}" --role="roles/storage.objectViewer"  2>&1
#gcloud storage buckets add-iam-policy-binding  gs://"${OUTPUT_BUCKET_NAME}" --member="serviceAccount:${JOB_SERVICE_ACCOUNT}" --role="roles/storage.objectViewer"  2>&1

#3 Otherwise geting 403 GET ERROR for config.json
gcloud projects add-iam-policy-binding $PROJECT_ID \
         --member="serviceAccount:${JOB_SERVICE_ACCOUNT}" \
         --role="roles/storage.admin"

# Creating bucket for config with versioning
create_bucket "${CONFIG_BUCKET_NAME}"
gsutil versioning set on "gs://${CONFIG_BUCKET_NAME}"

function substitute(){
  INPUT_FILE=$1
  OUTPUT_FILE=$2
  sed 's|__IMAGE__|'"$IMAGE_URI"'|g;
      s|__JXE_APP__|'"$JXE_APP"'|g;
      s|__OUT_BUCKET__|'"$OUTPUT_BUCKET_NAME"'|g;
      s|__IN_BUCKET__|'"$INPUT_BUCKET_NAME"'|g;
      s|__CONFIG_BUCKET__|'"$CONFIG_BUCKET_NAME"'|g;
      s|__DATA_BUCKET__|'"$DATA_BUCKET_NAME"'|g;
      ' "${INPUT_FILE}" > "${OUTPUT_FILE}"
}

$printf "Preparing config files" | tee -a "$LOG"

substitute "${DIR}/config/cram/cram_config_310.sample.json" "${DIR}/config/cram/cram_config_310.json"
substitute "${DIR}/config/cram/cram_config_403.sample.json" "${DIR}/config/cram/cram_config_403.json"
substitute "${DIR}/config/cram/cram_config.sample.json" "${DIR}/config/cram/cram_config.json"

substitute "${DIR}/config/cram/batch_config_403.sample.json" "${DIR}/config/cram/batch_config_403.json"
substitute "${DIR}/config/cram/batch_config_310.sample.json" "${DIR}/config/cram/batch_config_310.json"

substitute "${DIR}/config/fastq/fastq_config.sample.json" "${DIR}/config/fastq/fastq_config.json"
substitute "${DIR}/config/fastq/batch_config.sample.json" "${DIR}/config/fastq/batch_config.json"
substitute "${DIR}/config/fastq_list/fastq_list_config.sample.json" "${DIR}/config/fastq_list/fastq_list_config.json"
substitute "${DIR}/config/fastq_list/batch_config.sample.json" "${DIR}/config/fastq_list/batch_config.json"


gsutil cp "${DIR}/config/fastq/fastq_config.json" gs://"$CONFIG_BUCKET_NAME"/ | tee -a "$LOG"
gsutil cp "${DIR}/config/fastq_list/fastq_list_config.json" gs://"$CONFIG_BUCKET_NAME"/ | tee -a "$LOG"
gsutil cp "${DIR}/config/cram/cram_config.json" gs://"$CONFIG_BUCKET_NAME"/ | tee -a "$LOG"
gsutil cp "${DIR}/config/cram/cram_config_310.json" gs://"$CONFIG_BUCKET_NAME"/ | tee -a "$LOG"
gsutil cp "${DIR}/config/cram/cram_config_403.json" gs://"$CONFIG_BUCKET_NAME"/ | tee -a "$LOG"


gsutil cp "${DIR}/config/fastq_list/batch_config.json" gs://"$INPUT_BUCKET_NAME"/fastq_list_test/ | tee -a "$LOG"
gsutil cp "${DIR}/config/fastq_list/fastq_list.csv" gs://"$INPUT_BUCKET_NAME"/fastq_list_test/ | tee -a "$LOG"

gsutil cp "${DIR}/config/cram/batch_config_403.json" gs://"$INPUT_BUCKET_NAME"/cram_test/403/ | tee -a "$LOG"
gsutil cp "${DIR}/config/cram/batch_config_310.json" gs://"$INPUT_BUCKET_NAME"/cram_test/310/ | tee -a "$LOG"
gsutil cp "${DIR}/config/cram/NA12878_batch.txt" gs://"$INPUT_BUCKET_NAME"/cram_test/ | tee -a "$LOG"

gsutil cp "${DIR}/config/fastq/batch_config.json" gs://"$INPUT_BUCKET_NAME"/fastq_test/ | tee -a "$LOG"

bash -e "${DIR}"/deploy.sh | tee -a "$LOG"

$printf "Success! Infrastructure deployed and ready!"  | tee -a "$LOG"
echo "Next steps:"  | tee -a "$LOG"
echo " > Upload Required ORA files into gs://$INPUT_BUCKET_NAME/<your_folder>:"  | tee -a "$LOG"
echo " > Set reference data via gs://$INPUT_BUCKET_NAME/config.json"  | tee -a "$LOG"

echo " > Start the pipeline: "  | tee -a "$LOG"
echo "Drop empty file named START_PIPELINE inside gs://${INPUT_BUCKET_NAME}/<your_folder>"  | tee -a "$LOG"
echo "Or run following command:"  | tee -a "$LOG"
echo "./start_pipeline.sh <your_folder>"  | tee -a "$LOG"

timestamp=$(date +"%m-%d-%Y_%H:%M:%S")
echo "$timestamp Finished. Saved Log into $LOG"  | tee -a "$LOG"




