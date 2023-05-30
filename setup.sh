#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

LOG="$DIR/setup.log"
filename=$(basename $0)
timestamp=$(date +"%m-%d-%Y_%H:%M:%S")
echo "$timestamp - Running $filename ... " | tee "$LOG"

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

# gcloud services list --enabled|grep -v NAME|wc -l

# Enable APIs
echo "Enabling Required APIs..."  | tee -a "$LOG"

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

echo "Setting Org Policies..."  | tee -a "$LOG"
gcloud org-policies reset constraints/compute.vmExternalIpAccess --project=$PROJECT_ID
gcloud org-policies reset constraints/iam.disableServiceAccountKeyCreation --project=$PROJECT_ID
gcloud org-policies reset constraints/compute.requireShieldedVm --project=$PROJECT_ID
gcloud org-policies reset constraints/storage.restrictAuthTypes --project=$PROJECT_ID
sleep 10 # Otherwise fails on PreconditionException: 412 Request violates constraint 'constraints/iam.disableServiceAccountKeyCreation'

gcloud resource-manager org-policies describe    compute.trustedImageProjects --project=$PROJECT_ID    --effective > policy.yaml
echo "  - projects/illumina-dragen" >> policy.yaml
echo "  - projects/$GCLOUD_IMAGE_PROJECT" >> policy.yaml
echo "  - projects/$GCLOUD_BATCH_IMAGE_PROJECT" >> policy.yaml
gcloud resource-manager org-policies set-policy \
   policy.yaml --project=$PROJECT_ID
rm  policy.yaml

echo "Finished with Org policy Update"  | tee -a "$LOG"

network=$(gcloud compute networks list --filter="name=(\"$GCLOUD_NETWORK\" )" --format='get(NAME)' 2>/dev/null)
if [ -z "$network" ]; then
  echo "Creating Network $GCLOUD_NETWORK ..."  | tee -a "$LOG"
  gcloud compute networks create "$GCLOUD_NETWORK" --project="$PROJECT_ID" --subnet-mode=custom \
  --mtu=1460 --bgp-routing-mode=regional

  ## Use network name as subnet name (from Instructions)
  gcloud compute networks subnets create "$GCLOUD_SUBNET" --project="$PROJECT_ID" \
  --range=10.0.0.0/24 --stack-type=IPV4_ONLY --network="$GCLOUD_NETWORK" --region=us-central1

  gcloud compute --project="$PROJECT_ID" firewall-rules create ingress-ssh \
  --direction=INGRESS --priority=1000 --network="$GCLOUD_NETWORK" --action=ALLOW \
  --rules=tcp:22 --source-ranges=0.0.0.0/0
fi

gsutil ls "gs://${BUCKET_NAME}" 2> /dev/null
RETURN=$?
if [[ $RETURN -gt 0 ]]; then
    echo "Creating GCS Bucket gs://${TF_BUCKET_NAME}..."  | tee -a "$LOG"
    gsutil mb gs://$BUCKET_NAME
fi


SA_EXISTS=$(gcloud iam service-accounts list --filter="${SA_NAME_STORAGE}" | wc -l)
if [ $SA_EXISTS = "0" ]; then
  echo "Creating service account ${SA_NAME_STORAGE}..."  | tee -a "$LOG"
  gcloud iam service-accounts create $SA_NAME_STORAGE \
          --description="Storage Admin" \
          --display-name="storage-admin"
  gcloud projects add-iam-policy-binding $PROJECT_ID \
          --member="serviceAccount:${SA_EMAIL_STORAGE}" \
          --role="roles/storage.admin"
fi

[ ! -d "$DIR/tmp" ] && mkdir "$DIR/tmp"

echo "Creating HMAC keys..."  | tee -a "$LOG"
gsutil hmac create "$SA_EMAIL_STORAGE" > tmp/hmackey.txt
access_key=`cat  tmp/hmackey.txt  | awk  -F: '{print $2}' | xargs | awk '{print $1}'`
access_secret=`cat  tmp/hmackey.txt  | awk  -F: '{print $2}' | xargs | awk '{print $2}'`
echo "{\"access_key\": \"${access_key}\",  \"access_secret\": \"${access_secret}\" , \"endpoint\" : \"https://storage.googleapis.com\" }" > tmp/hmacsecret.json

exists=$(gcloud secrets describe ${S3_SECRET} 2> /dev/null)
if [ -z "$exists" ]; then
  echo "Creating ${S3_SECRET} secret..."  | tee -a "$LOG"
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
exists=$(gcloud secrets describe ${LICENCE_SECRET} 2> /dev/null)
if [ -z "$exists" ]; then
  echo "Creating $LICENCE_SECRET secret..."  | tee -a "$LOG"
  gcloud secrets create $LICENCE_SECRET --replication-policy="automatic" --project=$PROJECT_ID | tee -a "$LOG"
fi
gcloud secrets versions add $LICENCE_SECRET --data-file="tmp/licsecret.json" | tee -a "$LOG"
rm -rf tmp/licsecret.json # delete temp file

LICENCE_SECRET=$(gcloud secrets versions access latest --secret="$LICENCE_SECRET" --project=$PROJECT_ID | jq ".access_secret" | tr -d '"')
if [ -z "$LICENCE_SECRET" ] ; then
  echo "$LICENCE_SECRET was not created properly"
  echo "Try running following command to debug:"
  echo "  gcloud secrets versions access latest --secret=$LICENCE_SECRET --project=$PROJECT_ID "
  exit
else
  echo "Successfully created $LICENCE_SECRET secret."
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
  echo "Creating ${SA_JOB_NAME} Service Account to execute Batch Job"  | tee -a "$LOG"
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

echo "Preparing config.json file" | tee -a "$LOG"
sed 's|__IMAGE__|'"$IMAGE_URI"'|g;
    s|__JXE_APP__|'"$JXE_APP"'|g;
    s|__JXE_APP__|'"$JXE_APP"'|g;
    s|__OUT_BUCKET__|'"$OUTPUT_BUCKET"'|g;
    ' "${DIR}/cloud_function/config.sample.json" > "${DIR}/cloud_function/config.json"

gsutil cp "${DIR}/cloud_function/config.json" gs://"$BUCKET_NAME"/ | tee -a "$LOG"

bash -e "${DIR}"/deploy.sh | tee -a "$LOG"

echo "Success! Infrastructure deployed and ready!"  | tee -a "$LOG"
echo "Next steps:"  | tee -a "$LOG"
echo " > Upload data to gs://$BUCKET_NAME/<your_folder>:"  | tee -a "$LOG"
echo " -- R1x.ora into  gs://${BUCKET_NAME}/<your_folder>/inputs/xxR1xxx.ora"  | tee -a "$LOG"
echo " -- R2x.ora into  gs://${BUCKET_NAME}/<your_folder>/inputs/xxxR2xxx.ora"  | tee -a "$LOG"
echo " -- Reference data gs://${BUCKET_NAME}/<your_folder>/references/h38xxxx"  | tee -a "$LOG"
echo " -- lenadata inside gs://${BUCKET_NAME}/<your_folder>/references/lenadata"  | tee -a "$LOG"

echo " > Start the pipeline: "  | tee -a "$LOG"
echo "Drop empty file named START_PIPELINE inside gs://${BUCKET_NAME}/<your_folder>"  | tee -a "$LOG"
echo "Or run following command:"  | tee -a "$LOG"
echo "./start_pipeline.sh <your_folder>"  | tee -a "$LOG"

timestamp=$(date +"%m-%d-%Y_%H:%M:%S")
echo "$timestamp Finished. Saved Log into $LOG"  | tee -a "$LOG"




