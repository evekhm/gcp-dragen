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
import datetime
import os
from google.cloud import storage
from google.cloud.logging_v2.services.logging_service_v2 import LoggingServiceV2Client
import helper
from logging_handler import Logger

PROJECT_ID = os.getenv("GCP_PROJECT", os.environ.get("PROJECT_ID", ""))
# JOBS_INFO = os.getenv("JOBS_INFO")
assert PROJECT_ID, "PROJECT_ID is not set"
# assert JOBS_INFO, "JOBS_INFO is not set"
REGION = os.getenv('GCLOUD_REGION', "us-central1")

# API clients
storage_client = storage.Client()


def get_status(event, context):
    event_timestamp = ""
    if 'data' in event:
        data = base64.b64decode(event['data']).decode('utf-8')
        print(f'---- Received message:{data}')

        if "timestamp" in data and len(data.split("timestamp=")) > 1:
            event_timestamp = datetime.datetime.strptime(data.split("timestamp=")[1], "%Y-%m-%dT%H:%M:%S%z")
    Logger.info(f"---- Event received {event} with context {context}")

    if 'attributes' not in event:
        Logger.error("Received message is not in the expected format")
        return

    attributes = event['attributes']
    job_uid = attributes['JobUID']
    state = attributes['NewTaskState']
    task_id = attributes['TaskUID']
    Logger.info(f"Received task state change event for job_uid={job_uid}, new_state={state}, task_id={task_id}")

    client = LoggingServiceV2Client()

    resource_names = [f"projects/{PROJECT_ID}"]
    filters = (
        f"logName=projects/{PROJECT_ID}/logs/batch_task_logs "
        f""" AND resource.labels.task_id=task/{task_id}/0/0 AND resource.labels.job={job_uid}"""
    )
    Logger.info(f"filters={filters}")
    iterator = client.list_log_entries(
        {"resource_names": resource_names, "filter": filters}
    )

    sample_id = None
    input_type = "cram"  # For now only supported
    input_path = None
    output_path = None
    command = None

    for entry in iterator:
        if entry.text_payload.startswith("Command Line:"):
            command = entry.text_payload[len("Command Line:"):].strip()
            command = helper.obscure_sensitive_info(command)
            Logger.info(f"FOUND: {command}")
            input_path = helper.get_parameter_value(command, "--cram-input")
            output_path = helper.get_parameter_value(command, "--output-directory")
            sample_id = helper.get_parameter_value(command, "--vc-sample-name")
            break

    now = datetime.datetime.now()
    errors = helper.stream_document_to_bigquery([
        {
            "job_id": job_uid,
            "task_id": task_id,
            "sample_id": sample_id,
            "status": state,
            "event_timestamp": event_timestamp.strftime('%Y-%m-%d %H:%M:%S.%f'),
            "input_type": input_type,
            "input_path": input_path,
            "output_path": output_path,
            "command": command,
            "timestamp": now.strftime('%Y-%m-%d %H:%M:%S.%f')
        }

    ])
    if not errors:
        Logger.info(f"New rows have been added for "
                    f"case_id {job_uid} and {task_id}")
    elif isinstance(errors, list):
        error = errors[0].get("errors")
        Logger.error(f"Encountered errors while inserting rows "
                     f"for case_id {job_uid} and uid {task_id}: {error}")
    #Try to load file with name by job_uid
    # bucket_name, path = split_uri_2_bucket_prefix(f"gs://{JOBS_INFO}")


    # bucket = storage_client.bucket(bucket_name)
    # file_path = f"{path}/{job_uid}.csv"
    # stats = storage.Blob(bucket=bucket, name=file_path).exists(storage_client)
    # if stats:
    #     Logger.info(f"Loading samples data using gs://{bucket_name}/{file_path} file")
    #     blob = bucket.blob(file_path)
    #     csv_string = blob.download_as_text()
    #     f = StringIO(csv_string)
    #     reader = csv.reader(f, delimiter=',')
    #     new_rows = []
    #     for row in reader:
    #         csv_sample_id = row[0]
    #         csv_input_path = row[1]
    #         csv_job_name = row[2]
    #         csv_task_id = row[3]
    #         csv_output_path = row[4]
    #     #     log_query = f"logName=projects/{PROJECT_ID}/logs/batch_task_logs "
    #     # f"AND resource.labels.task_id=task/{job_uid}-group0-0/{task_nr}/0 AND resource.labels.job={job_uid}"
    #         if task_id == csv_task_id:
    #             Logger.info(f"Found!  task_id {task_id} corresponds to sample = {csv_sample_id}, input_path = {csv_input_path}, "
    #                         f"job_name={csv_job_name}, output_path = {csv_output_path}, log_file = ")


if __name__ == "__main__":
    get_status({
                    'attributes': {
                        "JobUID": "job-dragen-c2308d1-93a06b6f-358f-41160", "NewTaskState": "SUCCEEDED",
                        "TaskUID": "job-dragen-c2308d1-93a06b6f-358f-41160-group0-0"
                    },
                    'data':  'VGFzayBzdGF0ZSB3YXMgdXBkYXRlZDogdGFza1VJRD1qb2ItZHJhZ2VuLTgyNTBiMTUtMmZhZDg1YjYtNTcxOS00ZWNhMC1ncm91cDAtNCwgcHJldmlvdXNTdGF0ZT1QRU5ESU5HLCBjdXJyZW50U3RhdGU9U1VDQ0VFREVELCB0aW1lc3RhbXA9MjAyMy0wOC0xN1QxOTozMjo0Ni0wNzowMA=='
                }, None)



