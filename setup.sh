#!/bin/bash
gcloud config set project $PROJECT_ID

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}"/SET

echo "Setting Org Policies..."
gcloud services enable orgpolicy.googleapis.com

gcloud org-policies reset constraints/compute.vmExternalIpAccess --project=$PROJECT_ID
gcloud org-policies reset constraints/iam.disableServiceAccountKeyCreation --project=$PROJECT_ID
gcloud org-policies reset constraints/compute.requireShieldedVm --project=$PROJECT_ID
gcloud org-policies reset constraints/storage.restrictAuthTypes --project=$PROJECT_ID

gcloud resource-manager org-policies describe    compute.trustedImageProjects --project=$PROJECT_ID    --effective > policy.yaml
echo "  - projects/illumina-dragen" >> policy.yaml
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
export SA_NAME=storage-admin
export SA_EMAIL=${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com
gcloud iam service-accounts create $SA_NAME \
        --description="Storage Admin" \
        --display-name="storage-admin"
gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/storage.admin"

gsutil hmac create $SA_EMAIL
gsutil hmac list

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

echo "Service Account to execute batch Job"
gcloud services enable cloudresourcemanager.googleapis.com

# TODO Fine Grain Create Role
# # Create new Role
  ##compute.instances.create
  ##compute.instances.get

gcloud iam service-accounts create $SA_NAME \
        --description="Service Account to execute batch Job" \
        --display-name=$SA_NAME
gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/compute.serviceAgent"
gcloud projects add-iam-policy-binding $PROJECT_ID \
         --member="serviceAccount:${SA_EMAIL}" \
         --role="roles/compute.admin"





#export KEY=${PROJECT_ID}_${SA_NAME}.json
#gcloud iam service-accounts keys create ${KEY}  --iam-account=${SA_EMAIL}


