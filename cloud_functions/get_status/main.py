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
import re
from typing import List

from google.cloud import storage
from google.cloud.logging_v2.services.logging_service_v2 import LoggingServiceV2Client

from commonek.bq_helper import stream_data_to_bigquery, run_query
from commonek.logging import Logger
from commonek.params import (
    PROJECT_ID,
    DRAGEN_SUCCESS_ENTRIES,
    TASK_VERIFIED_OK,
    TASK_VERIFIED_FAILED,
    SUCCEEDED,
    FAILED,
    BIGQUERY_DB_TASKS,
    BIGQUERY_DB_JOB_ARRAY,

)
from commonek.slack import send_task_message

# API clients
storage_client = storage.Client()
client = LoggingServiceV2Client()


def is_dragen_success_check_logging(job_uid: str, task_id: str):
    def get_task_log_entries(payload_patterns: List[str]):
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

    log_entries, pattern = get_task_log_entries(DRAGEN_SUCCESS_ENTRIES)
    if log_entries and len(log_entries) > 0:
        return True
    return False


def get_task_info_from_bq(job_uid: str, task_id: str):
    regex = r"group0-(\d+)"
    match = re.search(regex, task_id)
    if match:
        task_index = match.group(1)
    else:
        Logger.warning(
            f"get_task_info_from_bq could not extract task index from task_id = {task_id}"
        )
        return None

    table_id = f"`{PROJECT_ID}.{BIGQUERY_DB_JOB_ARRAY}`"

    sql = f"SELECT sample_id, input_path, output_path, input_type, command FROM {table_id} WHERE " \
          f"job_id='{job_uid}' and batch_task_index={task_index}"

    results = run_query(sql)
    if results:
        for row in results:
            return row.sample_id, row.input_path, row.output_path, row.input_type, row.command
    else:
        return None, None, None, None, None


def get_status(event, context):
    Logger.info(f"============================ get_status - Event received {event} with context {context}")

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
    task_name = attributes["TaskName"]
    task_id = attributes["TaskUID"]
    region = attributes["Region"]
    Logger.info(
        f"get_status - Received task state change event for job_uid={job_uid}, new_state={state}, "
        f"task_id={task_id}, region={region}"
    )

    job_name = task_name.split("/")[5]
    sample_id, input_path, output_path, input_type, command = get_task_info_from_bq(job_uid=job_uid, task_id=task_id)

    save_task_to_bq(
        job_uid=job_uid,
        status=state,
        task_id=task_id,
    )

    if state == SUCCEEDED:
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

        save_task_to_bq(
            job_uid=job_uid,
            status=verification_status,
            task_id=task_id,
        )
        send_task_message(job_name=job_name, job_uid=job_uid, task_id=task_id, sample_id=sample_id,
                          status=verification_status,
                          output_path=output_path)

    elif state == FAILED:
        Logger.warning(f"get_status - Task Failed for job_uid={job_uid}, task_id={task_id}, "
                       f"sample_id={sample_id}")
        send_task_message(job_name=job_name, job_uid=job_uid, task_id=task_id, sample_id=sample_id, status=state)
    else:
        return


def save_task_to_bq(
    job_uid,
    status,
    task_id,
):
    now = datetime.datetime.now(datetime.timezone.utc)
    table_id = f"{PROJECT_ID}.{BIGQUERY_DB_TASKS}"
    errors = stream_data_to_bigquery(
        [
            {
                "job_id": job_uid,
                "task_id": task_id,
                "status": status,
                "timestamp": now.strftime("%Y-%m-%d %H:%M:%S"),
            }
        ], table_id
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

    # get_status(
    #     {
    #         "attributes": {
    #             "JobUID": "job-dragen-ae0e459-1866e3ae-c20b-4ce50",
    #             "NewTaskState": "SUCCEEDED",
    #             "TaskName": "projects/593129167048/locations/us-central1/jobs/job-dragen-ae0e459505/taskGroups/group0/tasks/0",
    #             "Region": "us-central1",
    #             "TaskUID": "job-dragen-ae0e459-1866e3ae-c20b-4ce50-group0-0",
    #             "Type": 'TASK_STATE_CHANGED'
    #         },
    #         "data": "VGFzayBzdGF0ZSB3YXMgdXBkYXRlZDogdGFza1VJRD1qb2ItZHJhZ2VuLWFlMGU0NTktMTg2NmUzYWUtYzIwYi00Y2U1MC1ncm91cDAtMCwgcHJldmlvdXNTdGF0ZT1QRU5ESU5HLCBjdXJyZW50U3RhdGU9U1VDQ0VFREVELCB0aW1lc3RhbXA9MjAyMy0wOS0yNlQxNzozNjo0MS0wNzowMA=='",
    #     },
    #     None,
    # )

    get_status(
        {
            "attributes": {
                "JobUID": "job-dragen-6279706-2b03e59e-c605-4e1b0",
                "NewTaskState": "VERIFIED_OK",
                "TaskName": "projects/593129167048/locations/us-central1/jobs/job-dragen-70a46a0fdd/taskGroups/group0/tasks/5",
                "Region": "us-central1",
                "TaskUID": "job-dragen-70a46a0-16c1bb08-dfe9-4e6e0-group0-5",
                "Type": 'TASK_STATE_CHANGED'
            },
            "data": "VGFzayBzdGF0ZSB3YXMgdXBkYXRlZDogdGFza1VJRD1qb2ItZHJhZ2VuLTgyMjM3YzMtYjFmNmMwZjQtNmIyNS00MTYyMC1ncm91cDAtMCwgcHJldmlvdXNTdGF0ZT1QRU5ESU5HLCBjdXJyZW50U3RhdGU9RkFJTEVELCB0aW1lc3RhbXA9MjAyMy0xMC0wNVQyMToxNzoxMS0wNzowMA==",
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
