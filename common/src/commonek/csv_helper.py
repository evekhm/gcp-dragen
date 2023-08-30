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

import csv
import json
import os
from io import StringIO

from google.cloud import storage

from commonek.helper import split_uri_2_bucket_prefix
from commonek.logging import Logger
from commonek.gcs_helper import file_exists
from commonek.params import TRIGGER_FILE_NAME, JOB_LABEL_NAME

# API clients
gcs = storage.Client()  # cloud storage


# uses CSV file with jobs list, to select and trigger next job (that comes as next row after previous_job_label or
# is first row if previous_job_label is none)
def trigger_job_from_csv(bucket_name: str, file_path: str, previous_job_label: str = None):
    Logger.info(f"trigger_job_from_csv - using gs://{bucket_name}/{file_path} scheduling file, "
                f"finding job listed after {previous_job_label} (or first if None)")

    if not file_exists(bucket_name, file_path):
        Logger.info(f"trigger_job_from_csv - Exiting since file gs://{bucket_name}/{file_path} i was not found.")
        return

    bucket = gcs.get_bucket(bucket_name)
    jobs_list_blob = bucket.blob(file_path)
    csv_string = jobs_list_blob.download_as_text()
    Logger.info(f"trigger_job_from_csv - scheduling file: [{csv_string}]")
    f = StringIO(csv_string)
    reader = csv.reader(f, delimiter=',')
    if not previous_job_label:
        next_row = True
    else:
        next_row = False

    for row in reader:
        if len(row) < 2:
            Logger.error(f"trigger_job_from_csv - Wrong format of the row {row}, "
                         f"should be: <job_label>, <batch_config_file_path.csv>")
            continue
        # <job_label>,  <batch_config_file_path.csv>
        job_label_name = row[0].strip()
        config_gcs = row[1].strip()

        if next_row:
            config_bucket_name, config_path = split_uri_2_bucket_prefix(config_gcs)

            # Constructing START_PIPELINE to upload to trigger job
            json_dic = {JOB_LABEL_NAME: job_label_name,
                        "config": os.path.basename(config_path)
                        }
            bucket = gcs.bucket(config_bucket_name)
            blob = bucket.blob(f"{os.path.dirname(config_path)}/{TRIGGER_FILE_NAME}")
            blob.upload_from_string(json.dumps(json_dic))
            Logger.info(f"trigger_job_from_csv - Uploading {json_dic} to gs://{config_bucket_name}/{blob.name} ")
            break

        if job_label_name == previous_job_label:
            next_row = True

    Logger.info(f"No job found to trigger comming after the completed one {previous_job_label}")