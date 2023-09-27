#!/bin/bash
WDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
printf="$WDIR/../utils/print"
source "${WDIR}/init_env_vars.sh" > /dev/null 2>&1

$printf "Updating organization policies: PROJECT_ID=${PROJECT_ID}"

# Enable Required API
gcloud services enable orgpolicy.googleapis.com

$printf "Setting up Policy Constraints..." INFO
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


echo "Waiting 30 seconds for Org Policy updates..."
sleep 30
$printf "Finished with Org Policy setup"  INFO