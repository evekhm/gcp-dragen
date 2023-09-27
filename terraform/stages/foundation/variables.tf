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


variable "env" {
  type    = string
  default = "dev"
}

variable "project_id" {
  type        = string
  description = "GCP Project ID"

  validation {
    condition     = length(var.project_id) > 0
    error_message = "The project_id value must be an non-empty string."
  }
}

variable "vpc_network" {
  type    = string
  default = "default"
}

variable "vpc_subnetwork" {
  type    = string
  default = "default"
}

variable "ip_cidr_range" {
  type    = string
  default = "10.0.0.0/24"
}

variable "region" {
  type        = string
  description = "Default GCP region"
  default     = "us-central1"

  validation {
    condition     = length(var.region) > 0
    error_message = "The region value must be an non-empty string."
  }
}

variable "bq_dataset_location" {
  type        = string
  description = "BigQuery Dataset location"
  default     = "US"
}

variable "storage_multiregion" {
  type    = string
  default = "us"
}

variable "job_service_account_name" {
  type        = string
  description = "Service account name for the Batch Job."
}

variable "dataset_id" {
  type        = string
  description = "Dataset ID"
  validation {
    condition     = length(var.dataset_id) > 0
    error_message = "The dataset_id value must be an non-empty string."
  }
}

variable "table_id" {
  type        = string
  description = "Table ID"
  validation {
    condition     = length(var.table_id) > 0
    error_message = "The table_id value must be an non-empty string."
  }
}

variable "dataset_location" {
  type        = string
  description = "BigQuery Dataset location"
  default     = "US"
}

variable "config_bucket" {
  type        = string
  description = "Bucket to store configuration "
}

variable "trigger_bucket" {
  type        = string
  description = "Bucket to store trigger data for the pipeline"
}

variable "output_bucket" {
  type        = string
  description = "Bucket to store DRAGEN output"
}

variable "data_bucket" {
  type        = string
  description = "Bucket to store DRAGEN samples input"
}

variable "pubsub_topic_batch_job_state_change" {
  type        = string
  description = "PUB SUB topic name for the batch job state change event"
}

variable "pubsub_topic_batch_task_state_change" {
  type        = string
  description = "PUB SUB topic name for the task state change event"
}

variable "illumina_lic_server_secret_data" {
  type        = string
  description = "Illumina License Server String in the format https://LICENSE_SECRET_KEY@license.edicogenome.com"
  validation {
    condition     = length(var.illumina_lic_server_secret_data) > 0
    error_message = "The License Server String must be an non-empty string."
  }
}

variable "illumina_lic_server_secret_name" {
  type    = string
  default = "illuminaLicServer"
}

variable "jarvice_api_key" {
  default = "JARVICE API key"
  type    = string
  validation {
    condition     = length(var.jarvice_api_key) > 0
    error_message = "The Jarvice API key must be an non-empty string."
  }
}

variable "jarvice_api_key_secret_name" {
  default = "jarviceApiKey"
  type    = string
}

variable "jarvice_api_username" {
  type = string
  validation {
    condition     = length(var.jarvice_api_username) > 0
    error_message = "The Jarvice API key must be an non-empty string."
  }
}

variable "jarvice_api_username_secret_name" {
  default = "jarviceApiUsername"
  type    = string
}