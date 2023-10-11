"""
Copyright 2022 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

import os

PROJECT_ID = os.getenv("GCP_PROJECT", os.environ.get("PROJECT_ID", ""))
assert PROJECT_ID, "PROJECT_ID is not set"

REGION = os.getenv("GCLOUD_REGION", "us-central1")
BIGQUERY_DB_TASKS = os.getenv("BIGQUERY_DB_TASKS", "dragen_illumina.tasks_status")
BIGQUERY_DB_JOB_ARRAY = os.getenv("BIGQUERY_DB_JOB_ARRAY", "dragen_illumina.job_array")

# DRAGEN INPUT TYPE
CRAM_INPUT = "cram"
FASTQ_LIST_INPUT = "fastq-list"
FASTQ_INPUT = "fastq"
######

JOB_LABEL_NAME = "dragen-job"

# Scheduler
JOBS_LIST_URI = os.getenv(
    "JOBS_LIST_URI", f"gs://{PROJECT_ID}-trigger/scheduler/jobs.csv"
)
JOB_LIST_FILE_NAME = os.path.basename(JOBS_LIST_URI)

TRIGGER_FILE_NAME = os.getenv("TRIGGER_FILE_NAME", "START_PIPELINE")

# header for Jobs
BATCH_TASK_INDEX = "BATCH_TASK_INDEX"
INPUT_TYPE = "INPUT_TYPE"
COMMAND = "COMMAND"

# Environment Variables
SAMPLE_ID = "SAMPLE_ID"
INPUT_PATH = "INPUT_PATH"
OUTPUT_PATH = "OUTPUT_PATH"

# Dragen CL Output
DRAGEN_COMMAND_ENTRIES = ["Command Line:"]  # Log Entry from Dragen Software
DRAGEN_SUCCESS_ENTRIES = [
    "DRAGEN finished normally",
    "DRAGEN complete\. Exiting",
]  # Either

# Task Job Status
SCHEDULED = "SCHEDULED"
SUCCEEDED = "SUCCEEDED"
FAILED = "FAILED"
TASK_VERIFIED_OK = "VERIFIED_OK"
TASK_VERIFIED_FAILED = "VERIFIED_FAILED"

# SLACK Integration
SLACK_CHANNEL = os.getenv("SLACK_CHANNEL")
SLACK_API_TOKEN_SECRET_NAME = os.getenv("SLACK_API_TOKEN_SECRET_NAME", "slack-api-token")

