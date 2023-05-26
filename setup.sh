#!/bin/bash
gcloud config set project $PROJECT_ID

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}"/SET

# Enable APIs
echo "Enabling Required APIs..."
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
sleep 5 #Todo check for operation wait to complete

# gcloud services list --enabled|grep -v NAME|wc -l
gcloud services enable $APIS

enabled=$(gcloud services list --enabled | grep compute)
while [ -z "$enabled" ]; do
  enabled=$(gcloud services list --enabled | grep compute)
  sleep 10;
done

echo "Setting Org Policies..."
gcloud org-policies reset constraints/compute.vmExternalIpAccess --project=$PROJECT_ID
gcloud org-policies reset constraints/iam.disableServiceAccountKeyCreation --project=$PROJECT_ID
gcloud org-policies reset constraints/compute.requireShieldedVm --project=$PROJECT_ID
gcloud org-policies reset constraints/storage.restrictAuthTypes --project=$PROJECT_ID
sleep 10 # Otherwise fails on PreconditionException: 412 Request violates constraint 'constraints/iam.disableServiceAccountKeyCreation'

gcloud resource-manager org-policies describe    compute.trustedImageProjects --project=$PROJECT_ID    --effective > policy.yaml
echo "  - projects/illumina-dragen" >> policy.yaml
echo "  - projects/atos-illumina-public" >> policy.yaml
echo "  - projects/batch-custom-image" >> policy.yaml
gcloud resource-manager org-policies set-policy \
   policy.yaml --project=$PROJECT_ID
rm  policy.yaml

echo "Finished with Org policy Update"

network=$(gcloud compute networks list --filter="name=(\"$GCLOUD_NETWORK\" )" --format='get(NAME)' 2>/dev/null)
if [ -z "$network" ]; then
  echo "Creating Network $GCLOUD_NETWORK ..."
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
    echo "Creating GCS Bucket gs://${TF_BUCKET_NAME}..."
    echo "Bucket does not exist, creating gs://${TF_BUCKET_NAME}"
    gsutil mb gs://$BUCKET_NAME
    echo
fi


SA_EXISTS=$(gcloud iam service-accounts list --filter="${SA_NAME_STORAGE}" | wc -l)
if [ $SA_EXISTS = "0" ]; then
  echo "Creating service account ${SA_NAME_STORAGE}..."
  gcloud iam service-accounts create $SA_NAME_STORAGE \
          --description="Storage Admin" \
          --display-name="storage-admin"
  gcloud projects add-iam-policy-binding $PROJECT_ID \
          --member="serviceAccount:${SA_EMAIL_STORAGE}" \
          --role="roles/storage.admin"
fi

[ ! -d "$DIR/tmp" ] && mkdir "$DIR/tmp"

echo "Creating HMAC keys..."
gsutil hmac create "$SA_EMAIL_STORAGE" > tmp/hmackey.txt
access_key=`cat  tmp/hmackey.txt  | awk  -F: '{print $2}' | xargs | awk '{print $1}'`
access_secret=`cat  tmp/hmackey.txt  | awk  -F: '{print $2}' | xargs | awk '{print $2}'`
echo "{\"access_key\": \"${access_key}\",  \"access_secret\": \"${access_secret}\" , \"endpoint\" : \"https://storage.googleapis.com\" }" > tmp/hmacsecret.json


exists=$(gcloud secrets describe ${S3_SECRET} 2> /dev/null)
if [ -z "$exists" ]; then
  echo "Creating ${S3_SECRET} secret..."
  gcloud secrets create $S3_SECRET --replication-policy="automatic" --project=$PROJECT_ID
fi
gcloud secrets versions add $S3_SECRET --data-file="tmp/hmacsecret.json"
rm -rf tmp/hmacsecret.json tmp/hmackey.txt # delete temp file


# Add secret file to Secret Manager
echo "{\"illumina_license\": \"${ILLUMINA_LICENSE}\",  \"jxe_apikey\": \"${JXE_APIKEY}\" , \"jxe_username\" : \"${JXE_USERNAME}\" }" > tmp/licsecret.json
exists=$(gcloud secrets describe ${LICENCE_SECRET} 2> /dev/null)
if [ -z "$exists" ]; then
  echo "Creating $LICENCE_SECRET secret..."
  gcloud secrets create $LICENCE_SECRET --replication-policy="automatic" --project=$PROJECT_ID
fi
gcloud secrets versions add $LICENCE_SECRET --data-file="tmp/licsecret.json"
rm -rf tmp/licsecret.json # delete temp file


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
  echo "Creating ${SA_JOB_NAME} Service Account to execute Batch Job"
  gcloud iam service-accounts create $SA_JOB_NAME \
          --description="Service Account to execute batch Job" \
          --display-name=$SA_JOB_NAME
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


bash -e "${DIR}"/deploy.sh

echo "Success! Infrastructure deployed and ready!"
echo "Next steps:"
echo " > Upload data to gs://$BUCKET_NAME/<your_folder>:"
echo " -- R1x.ora into  gs://${BUCKET_NAME}/<your_folder>/inputs"
echo " -- R2x.ora into  gs://${BUCKET_NAME}/<your_folder>/inputs"
echo " -- Reference data gs://${BUCKET_NAME}/<your_folder>/references"
echo " -- lenadata inside gs://${BUCKET_NAME}/<your_folder>/lendata"

echo " > Start the pipeline: "
echo "Drop empty file names START_PIPELINE inside gs://${BUCKET_NAME}/<your_folder>"
echo "Or run following command:"
echo "./start_pipeline.sh <your_folder>"




