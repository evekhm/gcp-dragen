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
import re
from google.cloud import batch_v1
from collections.abc import Iterable
from logging_handler import Logger
from google.cloud import bigquery
import os


PROJECT_ID = os.getenv("GCP_PROJECT", os.environ.get("PROJECT_ID", ""))
assert PROJECT_ID, "PROJECT_ID is not set"
BIGQUERY_DB = os.getenv('BIGQUERY_DB', "dragen_illumina.samples_status")
assert BIGQUERY_DB, "BIGQUERY_DB is not set"

bigquery_client = bigquery.Client()


def stream_document_to_bigquery(rows_to_insert):
    table_id = f"{PROJECT_ID}.{BIGQUERY_DB}"
    Logger.info(f"stream_document_to_bigquery table_id={table_id}, rows_to_insert={rows_to_insert}")

    errors = bigquery_client.insert_rows_json(table_id, rows_to_insert)
    return errors


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


def get_parameter_value(command: str, parameter_name: str):
    if parameter_name in command:
        try:
            return command.split(parameter_name)[1].strip().split(" ")[0]
        except Exception:
            return ""


def obscure_key(key_name, command):
    key_value = get_parameter_value(command, key_name)
    return command.replace(key_value, ('X' * len(key_value)))


def obscure_sensitive_info(command: str):
    license_string = get_parameter_value(command, "--lic-server")
    match = re.match(r"https://(.+)@license.edicogenome.com", license_string)
    if match and len(match.groups()) >= 1:
        lic = match.group(1)
        command = command.replace(lic, ('X' * len(lic)))

    keys_to_obscure = ["--apikey", "--s3-secret-key", "--s3-access-key"]
    for key in keys_to_obscure:
        command = obscure_key(key, command)
    return command