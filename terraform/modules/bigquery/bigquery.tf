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

#Creating a bigquery dataset and table schema

resource "google_bigquery_dataset" "data_set" {
  dataset_id    = var.dataset_id
  friendly_name = "Validation Dataset"
  description   = "BQ dataset for tasks/jobs/samples statuses"
  location      = "US"
}

resource "google_bigquery_table" "table_id" {
  depends_on = [
    google_bigquery_dataset.data_set
  ]

  deletion_protection = false
  dataset_id          = var.dataset_id
  table_id            = var.tasks_status_table_id

  schema = <<EOF
[
  {
    "name": "job_id",
    "type": "STRING",
    "mode": "Required",
    "description": "Id of the Batch Job used to create processing task"
  },
  {
    "name": "task_id",
    "type": "STRING",
    "mode": "Required",
    "description": "Id of the Task used to processing Dragen command"
  },
  {
    "name": "status",
    "type": "STRING",
    "mode": "Required",
    "description": "Status of the task as received"
  },
  {
    "name": "timestamp",
    "type": "DATETIME",
    "mode": "Required",
    "description": "Timestamp UTC"
  }
]
EOF

}

resource "google_bigquery_table" "job_array_table_id" {
  depends_on = [
    google_bigquery_dataset.data_set
  ]

  deletion_protection = false
  dataset_id          = var.dataset_id
  table_id            = var.job_array_table_id

  schema = <<EOF
[
  {
    "name": "job_id",
    "type": "STRING",
    "mode": "Required",
    "description": "Id of the Batch Job used to create processing task"
  },
  {
    "name": "job_name",
    "type": "STRING",
    "mode": "Required",
    "description": "Name of the Batch Job used to create processing task"
  },
  {
    "name": "job_label",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Optional job label when created"
  },
  {
    "name": "batch_task_index",
    "type": "INTEGER",
    "mode": "Required",
    "description": "Index in the batch Array"
  },
  {
    "name": "variables",
    "type": "JSON",
    "mode": "NULLABLE",
    "description": "Variables for the index array"
  },
  {
    "name": "sample_id",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "sample_id being processed"
  },
  {
    "name": "input_path",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "input path for the dragen processing"
  },
  {
    "name": "input_type",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Input type (CRAM, FASTQ, FASTQ_LIST)"
  },
  {
    "name": "output_path",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Path to the output directory"
  },
  {
    "name": "command",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Dragen command associated with the task (if found in the corresponding Log)"
  },
  {
    "name": "timestamp",
    "type": "DATETIME",
    "mode": "Required",
    "description": "Timestamp UTC"
  }
]
EOF

}
