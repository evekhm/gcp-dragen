#!/bin/bash
gcloud config set project $PROJECT_ID

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}"/../SET

# Enable APIs
gcloud services enable batch.googleapis.com compute.googleapis.com logging.googleapis.com # For batch Job
gcloud services enable cloudresourcemanager.googleapis.com # To grant roles to SA
gcloud services enable orgpolicy.googleapis.com # To modify Org Policies
gcloud services enable secretmanager.googleapis.com # To store Secrets
gcloud services enable cloudfunctions.googleapis.com # To deploy Cloud Function
gcloud services enable cloudbuild.googleapis.com # To deploy Cloud Function
gcloud services enable cloudresourcemanager.googleapis.com # For batch Job


echo "Setting Org Policies..."
gcloud org-policies reset constraints/compute.vmExternalIpAccess --project=$PROJECT_ID
gcloud org-policies reset constraints/iam.disableServiceAccountKeyCreation --project=$PROJECT_ID
gcloud org-policies reset constraints/compute.requireShieldedVm --project=$PROJECT_ID
gcloud org-policies reset constraints/storage.restrictAuthTypes --project=$PROJECT_ID

gcloud resource-manager org-policies describe    compute.trustedImageProjects --project=$PROJECT_ID    --effective > policy.yaml
echo "  - projects/illumina-dragen" >> policy.yaml
echo "  - projects/batch-custom-image" >> policy.yaml
gcloud resource-manager org-policies set-policy \
   policy.yaml --project=$PROJECT_ID

echo "Finished with Org policy Update"

gcloud services enable compute.googleapis.com
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

echo "Creating GCS Bucket ..."
gsutil mb gs://$BUCKET_NAME


echo "Creating HMAC keys and service account ..."
gcloud iam service-accounts create $SA_NAME_STORAGE \
        --description="Storage Admin" \
        --display-name="storage-admin"
gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${SA_EMAIL_STORAGE}" \
        --role="roles/storage.admin"

[ ! -d "$DIR/tmp" ] && mkdir "$DIR/tmp"
gsutil hmac create "$SA_EMAIL_STORAGE" > tmp/hmackey.txt
access_key=`cat  tmp/hmackey.txt  | awk  -F: '{print $2}' | xargs | awk '{print $1}'`
access_secret=`cat  tmp/hmackey.txt  | awk  -F: '{print $2}' | xargs | awk '{print $2}'`
echo "{\"access_key\": \"${access_key}\",  \"access_secret\": \"${access_secret}\" , \"endpoint\" : \"https://storage.googleapis.com\" }" > tmp/hmacsecret.json
gcloud secrets describe ${S3_SECRET}
if [ $? -eq 1 ]; then
  gcloud secrets create $S3_SECRET --replication-policy="automatic" --project=$PROJECT_ID
fi
gcloud secrets versions add $S3_SECRET --data-file="tmp/hmacsecret.json"
rm -rf tmp/hmacsecret.json tmp/hmackey.txt # delete temp file


# Add secret file to Secret Manager
echo "{\"illumina_license\": \"${ILLUMINA_LICENSE}\",  \"jxe_apikey\": \"${JXE_APIKEY}\" , \"jxe_username\" : \"${JXE_USERNAME}\" }" > tmp/licsecret.json
gcloud secrets describe ${LICENCE_SECRET}
if [ $? -eq 1 ]; then
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

echo "Service Account to execute Batch Job"


# TODO Fine Grain Create Role
# # Create new Role
  ##compute.instances.create
  ##compute.instances.get

gcloud iam service-accounts create $SA_JOB_NAME \
        --description="Service Account to execute batch Job" \
        --display-name=$SA_JOB_NAME
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


bash -e ${DIR}/




