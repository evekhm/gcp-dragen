/**
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

resource "google_service_account" "job_service_account" {
  account_id = var.job_service_account_name
}

resource "google_project_iam_member" "job_sa_iam" {
  depends_on = [google_service_account.job_service_account]
  for_each = toset([
    "roles/compute.admin",
    "roles/compute.serviceAgent",
    "roles/iam.serviceAccountUser",   # permissions  to create a job (https://cloud.google.com/batch/docs/create-run-job-custom-service-account)
    "roles/batch.jobsEditor",
    "roles/iam.serviceAccountViewer",
    "roles/logging.logWriter",    # For Log Monitoring
    "roles/batch.agentReporter",  # For Batch Job
    "roles/secretmanager.viewer",
    "roles/secretmanager.secretAccessor", # To access Secret
    "roles/artifactregistry.reader",  # To access AR
    "roles/artifactregistry.writer",  # To write Python Package to AR
    "roles/logging.admin",        # To Get Logging Analysis (Could be better scoped)
    "roles/storage.admin",        # Otherwise getting 403 GET ERROR for config.json
    "roles/bigquery.dataEditor",  # For BigQuery access (Could be narrowed down to the dataset)
    "roles/storage.objectCreator",
    "roles/bigquery.dataOwner"
  ])
  role    = each.key
  member  = "serviceAccount:${google_service_account.job_service_account.email}"
  project = var.project_id
}

#module "service_accounts" {
#  source       = "terraform-google-modules/service-accounts/google"
#  version      = "~> 3.0"
#  project_id   = var.project_id
#  names        = ["deployment-${var.env}"]
#  display_name = "deployment-${var.env}"
#  description  = "Deployment SA for ${var.env}"
#  project_roles = [for i in [
#    "roles/aiplatform.admin",
#    "roles/artifactregistry.admin",
#    "roles/cloudbuild.builds.builder",
#    "roles/cloudtrace.agent",
#    "roles/compute.admin",
#    "roles/container.admin",
#    "roles/containerregistry.ServiceAgent",
#    "roles/datastore.owner",
#    "roles/firebase.admin",
#    "roles/iam.serviceAccountTokenCreator",
#    "roles/iam.serviceAccountUser",
#    "roles/iam.workloadIdentityUser",
#    "roles/logging.admin",
#    "roles/logging.viewer",
#    "roles/run.admin",
#    "roles/secretmanager.secretAccessor",
#    "roles/storage.admin",
#    "roles/viewer",
#  ] : "${var.project_id}=>${i}"]
#  generate_keys = false
#}
