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

# project-specific locals
locals {
  services = [
    "pubsub.googleapis.com",               # PubSub
    "artifactregistry.googleapis.com",     # Artifact Registry
    "bigquery.googleapis.com",             # BigQuery
    "cloudbuild.googleapis.com",           # Cloud Build
    "compute.googleapis.com",              # Compute Engine
    "cloudresourcemanager.googleapis.com", # Cloud Resource Manager
    "iam.googleapis.com",                  # Cloud IAM
    "logging.googleapis.com",              # Cloud Logging
    "batch.googleapis.com",                # Batch API
    "secretmanager.googleapis.com",        # Secret Manager
    "cloudfunctions.googleapis.com",       # Cloud Functions
    "storage.googleapis.com",              # Cloud Storage
  ]
  multiregion        = var.storage_multiregion
  config_bucket_name = var.config_bucket
}

data "google_project" "project" {}
data "google_storage_project_service_account" "gcs_account" {}

module "project_services" {
  source     = "../../modules/project_services"
  project_id = var.project_id
  services   = local.services
}

module "hmac_keys" {
  depends_on = [module.project_services, module.service_accounts]
  source     = "../../modules/storage_hmac_key"
  project_id = var.project_id
}

module "service_accounts" {
  depends_on               = [module.project_services]
  source                   = "../../modules/service_accounts"
  project_id               = var.project_id
  env                      = var.env
  project_number           = data.google_project.project.number
  job_service_account_name = var.job_service_account_name
}

module "vpc_network" {
  depends_on     = [module.project_services]
  source         = "../../modules/vpc_network"
  project_id     = var.project_id
  vpc_network    = var.vpc_network
  region         = var.region
  vpc_subnetwork = var.vpc_subnetwork
  subnet_ip      = var.ip_cidr_range
}

# To use GCS CloudEvent triggers, the GCS service account requires the Pub/Sub Publisher(roles/pubsub.publisher) IAM role in the specified project.
# (See https://cloud.google.com/eventarc/docs/run/quickstart-storage#before-you-begin)
resource "google_project_iam_member" "gcs_pubsub_publishing" {
  project = data.google_project.project.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}

module "topic_batch_task_state_change_pubsub" {
  depends_on = [
    module.project_services,
    module.service_accounts,
    google_project_iam_member.gcs_pubsub_publishing
  ]
  source                = "../../modules/pubsub"
  topic                 = var.pubsub_topic_batch_task_state_change
  project_id            = var.project_id
  service_account_email = module.service_accounts.service_account_email
}


module "illumnia_lic_server_secret" {
  depends_on = [
    module.project_services,
    module.service_accounts,
  ]
  source      = "../../modules/secrets"
  secret_data = var.illumina_lic_server_secret_data
  secret_id   = var.illumina_lic_server_secret_name
}


module "jarvice_api_key_secret" {
  depends_on = [
    module.project_services,
    module.service_accounts,
  ]
  source      = "../../modules/secrets"
  secret_data = var.jarvice_api_key
  secret_id   = var.jarvice_api_key_secret_name
}

module "jarvice_api_username_secret" {
  depends_on = [
    module.project_services,
    module.service_accounts,
  ]
  source      = "../../modules/secrets"
  secret_data = var.jarvice_api_username
  secret_id   = var.jarvice_api_username_secret_name
}

module "topic_batch_job_state_change_pubsub" {
  depends_on = [
    module.project_services,
    module.service_accounts,
    google_project_iam_member.gcs_pubsub_publishing
  ]
  source                = "../../modules/pubsub"
  topic                 = var.pubsub_topic_batch_job_state_change
  project_id            = var.project_id
  service_account_email = module.service_accounts.service_account_email
}


module "bigquery" {
  depends_on            = [module.project_services, module.service_accounts]
  source                = "../../modules/bigquery"
  dataset_id            = var.dataset_id
  project_id            = var.project_id
  job_array_table_id    = var.job_array_table_id
  tasks_status_table_id = var.tasks_status_table_id
}


# Bucket to store config
resource "google_storage_bucket" "config" {
  name                        = var.config_bucket
  location                    = local.multiregion
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = true
  versioning {
    enabled = true
  }
}

resource "google_storage_bucket" "trigger_bucket" {
  name                        = var.trigger_bucket
  location                    = local.multiregion
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = true
}

resource "google_storage_bucket" "output_bucket" {
  name                        = var.output_bucket
  location                    = local.multiregion
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = true
}

resource "google_storage_bucket" "data_bucket" {
  name                        = var.data_bucket
  location                    = local.multiregion
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = true
}
