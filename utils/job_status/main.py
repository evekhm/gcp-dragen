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

# [START batch_create_script_job]
from __future__ import annotations

import argparse
import csv
import os
import re
from collections.abc import Iterable
from io import StringIO

from google.cloud import batch_v1
from google.cloud import storage
from google.cloud.logging_v2.services.logging_service_v2 import LoggingServiceV2Client

storage_client = storage.Client()

PROJECT_ID = os.getenv("GCP_PROJECT", os.environ.get("PROJECT_ID", ""))
JOBS_INFO = os.getenv("JOBS_INFO")

assert PROJECT_ID, "PROJECT_ID is not set"
assert JOBS_INFO, "JOBS_INFO is not set"
REGION = os.getenv('GCLOUD_REGION', "us-central1")


def split_uri_2_bucket_prefix(uri: str):
    match = re.match(r"gs://([^/]+)/(.+)", uri)
    if not match:
        # just bucket no prefix
        match = re.match(r"gs://([^/]+)", uri)
        return match.group(1), ""
    bucket = match.group(1)
    prefix = match.group(2)
    return bucket, prefix


def list_jobs(project_id: str, region: str) -> Iterable[batch_v1.Job]:
    """
    Get a list of all jobs defined in given region.

    Args:
        project_id: project ID or project number of the Cloud project you want to use.
        region: name of the region hosting the jobs.

    Returns:
        An iterable collection of Job object.
    """
    client = batch_v1.BatchServiceClient()

    return list(client.list_jobs(parent=f"projects/{project_id}/locations/{region}"))


def get_args():
    # Read command line arguments
    args_parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        description="""
      Script to Analyze log files of the Jobs as listed in the status.csv file.
      """,
        epilog="""
      Examples:

      python main.py -in=gs://path-to/job_list.csv  -out=gs://path-to/summary.csv
      """)

    args_parser.add_argument('-in', dest="in_file",
                             help="Path to input gs file uri with jobs list", required=True)
    args_parser.add_argument('-out', dest="out_file",
                             help="Path to output gs file uri with summary", required=True)
    return args_parser


SUCCESS = "completed"
FAILED = "failed"
UNKNOWN = "unknown"
RUNNING = "running"


def get_status(project_id: str, job_uid: str, task_nr: str):
    """Lists all logs in a project.

    Args:
        project_id: the ID of the project

    Returns:
        A list of log names.
    """
    client = LoggingServiceV2Client()

    resource_names = [f"projects/{project_id}"]
    filters = (
        f"logName=projects/{project_id}/logs/batch_task_logs "
        f"AND resource.labels.task_id=task/{job_uid}-group0-0/{task_nr}/0 AND resource.labels.job={job_uid}"
    )
    iterator = client.list_log_entries(
        {"resource_names": resource_names, "filter": filters}
    )
    for entry in iterator:
        if "DRAGEN complete. Exiting" in entry.text_payload:
            return SUCCESS, entry.timestamp

    return UNKNOWN, ""
        # if "Task" in entry.text_payload:
        #     found = True
        #     # If there are any results, exit loop
        #     break


def write_status_csv(rows, output_file):
    rows_str = "\n".join(rows)
    bucket_name, path = split_uri_2_bucket_prefix(output_file)
    bucket = storage_client.get_bucket(bucket_name)
    blob = bucket.blob(f"{path}")
    print(f"Uploading status information into gs://{bucket.name}/{path}")
    blob.upload_from_string(
        data=rows_str,
        content_type='text/csv')


def generate_summary(status_file: str):
    bucket_name, file_path = split_uri_2_bucket_prefix(status_file)
    bucket = storage_client.get_bucket(bucket_name)
    blob = bucket.blob(file_path)
    csv_string = blob.download_as_text()
    f = StringIO(csv_string)
    reader = csv.reader(f, delimiter=',')
    new_rows = []
    for row in reader:
        sample_id = row[0]
        input_path = row[1]
        job_name = row[2]
        task_nr = row[3]
        output_path = row[4]
        job_uid = row[5]
        print(f"Analyzing status for sample_id={sample_id}, input_path={input_path}, job_name={job_name}")
        status, timestamp = get_status(PROJECT_ID, job_uid, task_nr)
        new_row = row.extend([status, timestamp])
        new_rows.append(",".join(new_row))

    write_status_csv(new_rows, output_file)

if __name__ == "__main__":
    parser = get_args()
    args = parser.parse_args()
    in_file = args.in_file
    out_file = args.out_file
    generate_summary(in_file, out_file)
