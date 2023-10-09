#  Copyright 2022 Google LLC
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

from __future__ import annotations

import base64

from google.cloud import storage
from commonek.slack import send_job_message
from commonek.batch_helper import get_job_by_name
from commonek.csv_helper import trigger_job_from_csv
from commonek.helper import split_uri_2_bucket_prefix
from commonek.logging import Logger
from commonek.params import JOBS_LIST_URI, JOB_LABEL_NAME, SUCCEEDED, FAILED

# API clients
gcs = storage.Client()  # cloud storage


def get_job_update(event, context):
    Logger.info(f"============================ get_job_update - Event received {event} with context {context}")
    data = base64.b64decode(event["data"]).decode("utf-8")
    Logger.info(f"get_job_update - data={data}")

    if "attributes" not in event:
        Logger.error(
            "get_job_update - Received message is not in the expected format, missing attributes"
        )
        return

    attributes = event["attributes"]
    job_uid = attributes["JobUID"]
    job_name_full = attributes["JobName"]
    state = attributes["NewJobState"]
    region = attributes["Region"]
    Logger.info(
        f"get_job_update - Received job state change event for job_uid={job_uid}, new_state={state}, "
        f"job_name={job_name_full}"
        f" region={region}"
    )

    job_name = job_name_full.split("/")[-1]
    found_job = get_job_by_name(job_name=job_name)
    if state in [SUCCEEDED, FAILED]:
        send_job_message(job_name=job_name, job_uid=job_uid, status=state)
        Logger.info(
            f"get_job_update - Job state {state}, checking scheduling file {JOBS_LIST_URI} "
            f"for next job to trigger"
        )
        if found_job:
            if JOB_LABEL_NAME in found_job.labels:
                found_label = found_job.labels[JOB_LABEL_NAME]
                Logger.info(f"get_job_update - label = {found_label}")
                bucket_name, file_path = split_uri_2_bucket_prefix(JOBS_LIST_URI)
                trigger_job_from_csv(
                    bucket_name=bucket_name,
                    file_path=file_path,
                    previous_job_label=found_label,
                )
    else:
        Logger.info(
            f"get_job_update - Not triggering next job, since the state of the previous job = {state} does "
            f"not correspond to task completion, such as"
            f" {SUCCEEDED} or {FAILED}"
        )


if __name__ == "__main__":
    get_job_update(
        {
            "attributes": {
                "JobName": "projects/593129167048/locations/us-central1/jobs/job-dragen-ae0e459505",
                "JobUID": "job-dragen-ae0e459-1866e3ae-c20b-4ce50",
                "NewJobState": "SUCCEEDED",
                "Region": "us-central1",
            },
            "data": "Sm9iIHN0YXRlIHdhcyB1cGRhdGVkOiBqb2JOYW1lPXByb2plY3RzLzg3MTc5MDE5MzQ2Ny9sb2NhdGlvbnMvdXMtY2VudHJhbDEvam9icy9qb2ItZHJhZ2VuLWU1ZDJiMjJlMmJkMjRlOWE5MDJlZWMyMmE4ODhkZGM3LCBqb2JVSUQ9am9iLWRyYWdlbi1lNWQyYjIyLTNmYzg1M2Y5LTJlOWItNGYwODAsIHByZXZpb3VzU3RhdGU9UlVOTklORywgY3VycmVudFN0YXRlPVNVQ0NFRURFRCwgdGltZXN0YW1wPTIwMjMtMDgtMjRUMTY6MjE6MTQtMDc6MDA=",
        },
        None,
    )

    # get_job_update({
    #     'attributes': {
    #         "JobName": "projects/871790193467/locations/us-central1/jobs/job-dragen-e5d2b22e2bd24e9a902eec22a888ddc7",
    #         "JobUID": "job-dragen-e5d2b22-3fc853f9-2e9b-4f080",
    #         "NewJobState": "FAILED",
    #         'Region': 'us-central1'
    #     },
    #     'data':  'Sm9iIHN0YXRlIHdhcyB1cGRhdGVkOiBqb2JOYW1lPXByb2plY3RzLzg3MTc5MDE5MzQ2Ny9sb2NhdGlvbnMvdXMtY2VudHJhbDEvam9icy9qb2ItZHJhZ2VuLWU1ZDJiMjJlMmJkMjRlOWE5MDJlZWMyMmE4ODhkZGM3LCBqb2JVSUQ9am9iLWRyYWdlbi1lNWQyYjIyLTNmYzg1M2Y5LTJlOWItNGYwODAsIHByZXZpb3VzU3RhdGU9UlVOTklORywgY3VycmVudFN0YXRlPVNVQ0NFRURFRCwgdGltZXN0YW1wPTIwMjMtMDgtMjRUMTY6MjE6MTQtMDc6MDA='
    # }, None)
