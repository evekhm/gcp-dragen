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
import csv
import datetime
import os
import re
from io import StringIO
from typing import List

from google.cloud import storage
from google.cloud.logging_v2.services.logging_service_v2 import LoggingServiceV2Client

from commonek.batch_helper import get_job_by_uid
from commonek.bq_helper import stream_tasks_to_bigquery
from commonek.dragen_command_helper import DragenCommand
from commonek.helper import split_uri_2_bucket_prefix
from commonek.logging import Logger
from commonek.params import (
    PROJECT_ID,
    JOBS_INFO_PATH,
    SAMPLE_ID,
    INPUT_PATH,
    OUTPUT_PATH,
    JOB_LABEL_NAME,
    INPUT_TYPE,
    COMMAND,
    DRAGEN_COMMAND_ENTRIES,
    DRAGEN_SUCCESS_ENTRIES,
    TASK_VERIFIED_OK,
    TASK_VERIFIED_FAILED,
    TASK_SUCCEEDED,
)

# API clients
storage_client = storage.Client()
client = LoggingServiceV2Client()


def get_task_info_from_csv(job_uid: str, task_id: str):
    Logger.info(
        f"get_task_info_from_csv with status_dir={JOBS_INFO_PATH}, job_uid = {job_uid}, task_id = {task_id}"
    )
    regex = r"group0-(\d+)"
    match = re.search(regex, task_id)
    if match:
        task_index = match.group(1)
    else:
        Logger.warning(
            f"get_task_info_from_csv could not extract task index from task_id =  {task_id}"
        )
        return None

    bucket_name, file_path = split_uri_2_bucket_prefix(
        os.path.join(JOBS_INFO_PATH, f"{job_uid}.csv")
    )
    bucket = storage_client.get_bucket(bucket_name)
    blob = bucket.blob(file_path)
    csv_string = blob.download_as_text()
    f = StringIO(csv_string)
    reader = csv.reader(f, delimiter=",")

    def get_index(param_name):
        if param_name in row:
            return row.index(param_name)
        return None

    (
        output_path_index,
        input_type_index,
        command_index,
        sample_id_index,
        input_path_index,
    ) = (None, None, None, None, None)
    sample_id, input_path, output_path, input_type, command = (
        None,
        None,
        None,
        None,
        None,
    )
    task_row = None
    is_first_row = True

    for row in reader:
        if is_first_row:
            # skip header
            command_index = get_index(COMMAND)
            sample_id_index = get_index(SAMPLE_ID)
            input_path_index = get_index(INPUT_PATH)
            output_path_index = get_index(OUTPUT_PATH)
            input_type_index = get_index(INPUT_TYPE)
            is_first_row = False
            continue
        index = row[0]
        if index == task_index:
            task_row = row
            break

    if task_row is not None:
        if input_type_index:
            input_type = task_row[input_type_index]
        if sample_id_index:
            sample_id = task_row[sample_id_index]
        if command_index:
            command = task_row[command_index]
        if input_path_index:
            input_path = task_row[input_path_index]
        if output_path_index:
            output_path = task_row[output_path_index]

        if command:
            dragen_command = DragenCommand(command)
            if not sample_id:
                sample_id = dragen_command.get_sample_id()
            if not input_path:
                input_path = dragen_command.get_input()
            if not output_path:
                output_path = dragen_command.get_output()

    Logger.info(
        f"get_task_info_from_csv return sample_id={sample_id}, input_path={input_path}, "
        f"output_path={output_path}, input_type={input_type}, command={command}"
    )

    return sample_id, input_path, output_path, input_type, command


def get_log_entries(job_uid: str, task_id: str, payload_patterns: List[str]):
    Logger.info(
        f"get_log_entry with job_uid={job_uid}, task_id={task_id},"
        f" payload={','.join(payload_patterns)}"
    )

    resource_names = [f"projects/{PROJECT_ID}"]

    for payload_pattern in payload_patterns:
        filters = (
            f"logName=projects/{PROJECT_ID}/logs/batch_task_logs "
            f""" AND resource.labels.task_id=task/{task_id}/0/0 AND resource.labels.job={job_uid} AND
             textPayload=~\"{payload_pattern}\""""
        )
        Logger.info(f"get_log_entry filters={filters}")
        iterator = client.list_log_entries(
            {"resource_names": resource_names, "filter": filters}
        )

        payload = [entry.text_payload for entry in iterator]
        if payload and len(payload) > 0:
            return payload, payload_pattern
    return None, None


def is_dragen_success_check_logging(job_uid: str, task_id: str):
    log_entries = get_log_entries(job_uid, task_id, DRAGEN_SUCCESS_ENTRIES)
    if log_entries and len(log_entries) > 0:
        return True
    return False


def get_task_info_from_log(job_uid: str, task_id: str):
    sample_id, input_path, output_path, command, input_type = (
        None,
        None,
        None,
        None,
        None,
    )

    log_entries, pattern = get_log_entries(job_uid, task_id, DRAGEN_COMMAND_ENTRIES)
    if log_entries and len(log_entries) > 0:
        # taking last log Entry
        last_entry = log_entries[-1]
        command = last_entry[len(pattern) :].strip()
        dragen_command = DragenCommand(command)
        Logger.info(f"get_task_info_from_log - FOUND: {dragen_command}")
        input_path = dragen_command.get_input()
        output_path = dragen_command.get_output()
        sample_id = dragen_command.get_sample_id()
        input_type = dragen_command.get_input_type()

    return sample_id, input_path, output_path, input_type, command


def get_status(event, context):
    Logger.info(f"get_status - Event received {event} with context {context}")

    data = base64.b64decode(event["data"]).decode("utf-8")
    Logger.info(f"get_status - data={data}")

    if "attributes" not in event:
        Logger.error(
            "get_status - Received message is not in the expected format, missing attributes"
        )
        return

    attributes = event["attributes"]
    job_uid = attributes["JobUID"]
    state = attributes["NewTaskState"]
    task_id = attributes["TaskUID"]
    region = attributes["Region"]
    Logger.info(
        f"get_status - Received task state change event for job_uid={job_uid}, new_state={state}, "
        f"task_id={task_id}, region={region}"
    )

    task_info = get_task_info_from_csv(job_uid=job_uid, task_id=task_id)
    if not task_info:
        task_info = get_task_info_from_log(job_uid=job_uid, task_id=task_id)

    job = get_job_by_uid(job_uid)
    if job:
        labels = job.labels[JOB_LABEL_NAME]
    else:
        labels = {}

    sample_id, input_path, output_path, input_type, command = task_info
    now = datetime.datetime.now(datetime.timezone.utc)
    save_task_to_bq(
        command,
        input_path,
        input_type,
        job_uid,
        labels,
        now,
        output_path,
        sample_id,
        state,
        task_id,
    )

    if state == TASK_SUCCEEDED:
        Logger.info(
            f"get_status - Running Verification step for job_uid={job_uid}, task_id={task_id}, "
            f"sample_id={sample_id}"
        )
        # Do verification using Log
        verification_status = TASK_VERIFIED_FAILED
        if is_dragen_success_check_logging(job_uid, task_id):
            verification_status = TASK_VERIFIED_OK
        Logger.info(
            f"get_status - Complete Verification step for job_uid={job_uid}, task_id={task_id}, "
            f"sample_id={sample_id} - verification_status={verification_status}"
        )
        now = datetime.datetime.now(datetime.timezone.utc)
        save_task_to_bq(
            command,
            input_path,
            input_type,
            job_uid,
            labels,
            now,
            output_path,
            sample_id,
            verification_status,
            task_id,
        )


def save_task_to_bq(
    command,
    input_path,
    input_type,
    job_uid,
    labels,
    now,
    output_path,
    sample_id,
    state,
    task_id,
):
    errors = stream_tasks_to_bigquery(
        [
            {
                "job_id": job_uid,
                "job_label": labels,
                "task_id": task_id,
                "sample_id": sample_id,
                "status": state,
                "input_type": input_type,
                "input_path": input_path,
                "output_path": output_path,
                "command": command,
                "timestamp": now.strftime("%Y-%m-%d %H:%M:%S"),
            }
        ]
    )
    if not errors:
        Logger.info(
            f"get_status - New rows have been added for job_uid={job_uid}, task_id={task_id}"
        )
    elif isinstance(errors, list):
        error = errors[0].get("errors")
        Logger.error(
            f"get_status - Encountered errors while inserting rows "
            f"for case_id {job_uid} and uid {task_id}: {error}"
        )


if __name__ == "__main__":
    # Using Logger (cram)
    # get_status({
    #                 'attributes': {
    #                     "JobUID": "job-dragen-c2308d1-93a06b6f-358f-41160", "NewTaskState": "SUCCEEDED",
    #                     "TaskUID": "job-dragen-c2308d1-93a06b6f-358f-41160-group0-0"
    #                 },
    #                 'data':  'VGFzayBzdGF0ZSB3YXMgdXBkYXRlZDogdGFza1VJRD1qb2ItZHJhZ2VuLTgyNTBiMTUtMmZhZDg1YjYtNTcxOS00ZWNhMC1ncm91cDAtNCwgcHJldmlvdXNTdGF0ZT1QRU5ESU5HLCBjdXJyZW50U3RhdGU9U1VDQ0VFREVELCB0aW1lc3RhbXA9MjAyMy0wOC0xN1QxOTozMjo0Ni0wNzowMA=='
    #             }, None)

    # Using csv (cram)
    # get_task_info_from_log("job-dragen-73a1ea4-a2c792ba-50a8-43190",
    #                        "job-dragen-73a1ea4-a2c792ba-50a8-43190-group0-0")
    #
    # is_dragen_success_check_logging(job_uid="job-dragen-73a1ea4-a2c792ba-50a8-43190",
    #                                 task_id="job-dragen-73a1ea4-a2c792ba-50a8-43190-group0-0")

    get_status(
        {
            "attributes": {
                "JobUID": "dragen-job-2f2440c-34be57a5-bb2a-42f70",
                "NewTaskState": "SUCCEEDED",
                "Region": "us-central1",
                "TaskUID": "dragen-job-2f2440c-34be57a5-bb2a-42f70-group0-0",
            },
            "data": "VGFzayBzdGF0ZSB3YXMgdXBkYXRlZDogdGFza1VJRD1kcmFnZW4tam9iLTJmMjQ0MGMtMzRiZTU3YTUtYmIyYS00MmY3MC1ncm91cDAtMCwgcHJldmlvdXNTdGF0ZT1SVU5OSU5HLCBjdXJyZW50U3RhdGU9U1VDQ0VFREVELCB0aW1lc3RhbXA9MjAyMy0wOS0yMFQxMDo1ODozMC0wNzowMA==",
        },
        None,
    )

    # get_status({
    #     'attributes': {
    #         "JobUID": "job-dragen-e5d2b22-3fc853f9-2e9b-4f080", "NewTaskState": "SUCCEEDED", 'Region': 'us-central1',
    #         "TaskUID": "job-dragen-e5d2b22-3fc853f9-2e9b-4f080-group0-6"
    #     },
    #     'data': 'VGFzayBzdGF0ZSB3YXMgdXBkYXRlZDogdGFza1VJRD1qb2ItZHJhZ2VuLWU1ZDJiMjItM2ZjODUzZjktMmU5Yi00ZjA4MC1ncm91cDAtNiwgcHJldmlvdXNTdGF0ZT1QRU5ESU5HLCBjdXJyZW50U3RhdGU9U1VDQ0VFREVELCB0aW1lc3RhbXA9MjAyMy0wOC0yNFQxNjoyMTowMy0wNzowMA=='
    # }, None)

    # Using Logger (fastq)

    # Using csv (fastq)
