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

from google.cloud import storage
from commonek.helper import split_uri_2_bucket_prefix
from commonek.logging import Logger

storage_client = storage.Client()


def get_rows_from_file(file_uri: str, skip_header=True):
    Logger.info(f"get_rows_from_file - {file_uri}")
    bucket_name, file_name = split_uri_2_bucket_prefix(file_uri)

    bucket = storage_client.get_bucket(bucket_name)

    blob = bucket.blob(file_name)
    text = blob.download_as_text().replace("\r", "").replace("\t", " ")
    lines = text.split("\n")

    rows = []
    line_nr = 0
    for line in lines:
        line_nr += 1
        if line_nr == 1 and skip_header:
            Logger.info(f"get_rows_from_file - Skipping first line {line}")
            continue
        line = line.strip()
        if line != "":
            rows.append(line.split())

    Logger.info(f"get_rows_from_file - Read {line_nr} lines from {file_uri}")
    return rows


def file_exists(bucket_name: str, file_name: str):
    bucket = storage_client.bucket(bucket_name)
    stats = storage.Blob(bucket=bucket, name=file_name).exists(storage_client)
    return stats


def write_gcs_blob(bucket_name, file_name, content_as_str, content_type="text/plain"):
    bucket = storage_client.get_bucket(bucket_name)
    gcs_file = bucket.blob(file_name)
    gcs_file.upload_from_string(content_as_str, content_type=content_type)
    Logger.debug(f"Saving the file {file_name} to GCS bucket {bucket_name}")
