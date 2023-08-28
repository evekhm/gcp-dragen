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
from collections.abc import Iterable
from google.cloud import batch_v1

from commonek.params import PROJECT_ID, REGION


def list_jobs() -> Iterable[batch_v1.Job]:
    """
    Get a list of all jobs defined in given region.

    Returns:
        An iterable collection of Job object.
    """
    client = batch_v1.BatchServiceClient()

    return list(client.list_jobs(parent=f"projects/{PROJECT_ID}/locations/{REGION}"))


def get_job_by_name(job_name: str) -> batch_v1.Job:
    """
    Retrieve information about a Batch Job.

    Args:
        job_name: the name of the job you want to retrieve information about.

    Returns:
        A Job object representing the specified job.
    """
    client = batch_v1.BatchServiceClient()

    return client.get_job(
        name=f"projects/{PROJECT_ID}/locations/{REGION}/jobs/{job_name}"
    )


def get_job_by_uid(job_uid: str) -> batch_v1.Job:
    """
    Get a list of all jobs defined in given region.

    Args:
        job_uid: id of the job.

    Returns:
        A Job object representing the specified job.
    """
    client = batch_v1.BatchServiceClient()

    for job in list(client.list_jobs(parent=f"projects/{PROJECT_ID}/locations/{REGION}")):
        if job.uid == job_uid:
            return job

