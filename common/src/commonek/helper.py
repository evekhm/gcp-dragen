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
from google.cloud import secretmanager
from commonek.logging import Logger
sm = None  # secret_manager
from google.api_core.exceptions import NotFound

def split_uri_2_bucket_prefix(uri: str):
    match = re.match(r"gs://([^/]+)/(.+)", uri)
    if not match:
        # just bucket no prefix
        match = re.match(r"gs://([^/]+)", uri)
        if not match:
            return split_uri_2_bucket_s3(uri)
        return match.group(1), ""
    bucket = match.group(1)
    prefix = match.group(2)
    return bucket, prefix


def split_uri_2_bucket_s3(uri: str):
    match = re.match(r"s3://([^/]+)/(.+)", uri)
    if not match:
        # just bucket no prefix
        match = re.match(r"s3://([^/]+)", uri)
        if not match:
            return "", ""
        return match.group(1), ""
    bucket = match.group(1)
    prefix = match.group(2)
    return bucket, prefix


def get_secret_value(secret_name, project_id):
    global sm
    if not sm:
        sm = secretmanager.SecretManagerServiceClient()

    secret_path = f"projects/{project_id}/secrets/{secret_name}/versions/latest"

    try:
        response = sm.access_secret_version(request={"name": secret_path})
        payload = response.payload.data.decode("UTF-8")
        return payload
    except NotFound as exc:
        Logger.warning(f"Secret not found {secret_name} {exc}")
        return None


def hello_world(text="Hello World"):
    print(text)
