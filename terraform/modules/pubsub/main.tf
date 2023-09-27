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

#Creating a pubsub resource for queue

#creating pubsub topic
resource "google_pubsub_topic" "pubsub_topic" {
  name = var.topic
}

resource "google_pubsub_topic_iam_binding" "binding_editor" {
  project         = var.project_id
  topic = google_pubsub_topic.pubsub_topic.name
  role = "roles/pubsub.editor"
  members = [
    "serviceAccount:${var.service_account_email}",
  ]
}

resource "google_pubsub_topic_iam_binding" "binding_publisher" {
  project         = var.project_id
  topic = google_pubsub_topic.pubsub_topic.name
  role = "roles/pubsub.publisher"
  members = [
    "serviceAccount:${var.service_account_email}",
  ]
}

