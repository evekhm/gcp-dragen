/**
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  #hmac_key_secret_file = "hmac_key.secret"
  hmac_key_access_file = "${path.module}/hmac_key.access"
  hmac_key_secret_file = "${path.module}/hmac_key.secret"
}

resource "google_service_account" "service_account" {
  account_id = "storage-admin"
}

resource "google_project_iam_member" "storage-admin-iam" {
  for_each = toset([
    "roles/storage.admin",
  ])
  role    = each.key
  member  = "serviceAccount:${google_service_account.service_account.email}"
  project = var.project_id
}

# Create the HMAC key for the associated service account
resource "google_storage_hmac_key" "hmac-key" {
  service_account_email = google_service_account.service_account.email
  depends_on = [
    google_service_account.service_account,
  ]
}

resource "local_sensitive_file" "hmac_secret" {
  content  = google_storage_hmac_key.hmac-key.secret
  filename = local.hmac_key_secret_file
}

resource "local_sensitive_file" "hmac_access_id" {
  content  = google_storage_hmac_key.hmac-key.access_id
  filename = local.hmac_key_access_file
}

resource "google_secret_manager_secret" "hmac_key_secret" {
  secret_id = "batchS3SecretKey"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "hmac_key_access" {
  secret_id = "batchS3AccessKey"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "hmac_key_secret_data" {
  secret      = google_secret_manager_secret.hmac_key_secret.id
  secret_data = local_sensitive_file.hmac_secret.content
  depends_on = [google_secret_manager_secret.hmac_key_secret]
}

resource "google_secret_manager_secret_version" "hmac_key_access_data" {
  secret      = google_secret_manager_secret.hmac_key_access.id
  secret_data = local_sensitive_file.hmac_access_id.content
  depends_on = [google_secret_manager_secret.hmac_key_access]
}
