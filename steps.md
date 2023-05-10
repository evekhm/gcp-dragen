## Setup
* Create Network and subnetwork

```shell
gcloud services enable compute.googleapis.com
gcloud compute networks create default --project="$PROJECT_ID"

gcloud compute networks create default --project="$PROJECT_ID" --subnet-mode=custom \
--mtu=1460 --bgp-routing-mode=regional 
 
gcloud compute networks subnets create default-subnet --project="$PROJECT_ID" \
--range=10.0.0.0/24 --stack-type=IPV4_ONLY --network=default --region=us-central1

gcloud compute --project="$PROJECT_ID" firewall-rules create ingress-ssh \
--direction=INGRESS --priority=1000 --network=default --action=ALLOW \
--rules=tcp:22 --source-ranges=0.0.0.0/0

```
* Create bucket:
  * inputs - folder
  * references - folder
* Disable Org Policy Constraints
```shell
gcloud services enable orgpolicy.googleapis.com
gcloud org-policies reset constraints/compute.vmExternalIpAccess --project=$PROJECT_ID
gcloud org-policies reset constraints/iam.disableServiceAccountKeyCreation --project=$PROJECT_ID
gcloud org-policies reset constraints/compute.requireShieldedVm --project=$PROJECT_ID
gcloud org-policies reset constraints/storage.restrictAuthTypes --project=$PROJECT_ID
```
* Upload data
* Create service account (Cloud Storage admin) and generate HMAC key (S3 protocol)

```shell
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
```

```shell
# Create a new service account
resource "google_service_account" "service_account" {
  account_id = "my-svc-acc"
}

# Create the HMAC key for the associated service account
resource "google_storage_hmac_key" "key" {
  service_account_email = google_service_account.service_account.email
}
```

