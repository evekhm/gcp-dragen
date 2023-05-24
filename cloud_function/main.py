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
import os
import uuid

from google.cloud import batch_v1



def run_job(event, context):
    project_id = os.getenv('GCP_PROJECT')
    region = os.getenv('REGION', "us-central1")
    job_name = os.getenv('JOB_NAME', "dragen-job")
    network = os.getenv('NETWORK', "default")
    subnet = os.getenv('SUBNET', "default")
    service_account_email = os.getenv('SERVICE_ACCOUNT_EMAIL', "")
    machine = os.getenv('MACHINE', "n1-standard-2")
    print(f"Using PROJECT_ID = {project_id}, region = {region},"
          f" job_name = {job_name}, network = {network},"
          f" subnet = {subnet}, service_account_email = {service_account_email},"
          f" machine = {machine}")

    print(event)
    bucket = None
    file_name = None
    if 'bucket' in event:
        bucket = event['bucket']

    if "name" in event:
        file_name = event['name']

    assert bucket, "Bucket unknown"
    assert file_name, "Filename unknown"

    # file=inputs/START_PIPELINE
    # bucket
    print(f"Received GCS finalized event on bucket={bucket}, file={file_name} ")

    return create_script_job(project_id=project_id, region=region,
                             job_name=job_name, network=network, subnet=subnet,
                             bucket=bucket,
                             service_account_email=service_account_email, machine=machine)


def create_script_job(project_id: str, region: str, network: str,
    subnet: str, job_name: str, bucket: str, service_account_email: str,
    machine: str) -> batch_v1.Job:
    """
    This method shows how to create a sample Batch Job that will run
    a simple command on Cloud Compute instances.

    Args:
        project_id: project ID or project number of the Cloud project you want to use.
        region: name of the region you want to use to run the job. Regions that are
            available for Batch are listed on: https://cloud.google.com/batch/docs/get-started#locations
        job_name: the name of the job that will be created.
            It needs to be unique for each project and region pair.

    Returns:
        A job object representing the job created.
    """
    client = batch_v1.BatchServiceClient()

    # Define what will be done as part of the job.
    runnable = batch_v1.Runnable()
    runnable.container = batch_v1.Runnable.Container()
    runnable.container.image_uri = "gcr.io/google-containers/busybox"
    runnable.container.entrypoint = "/bin/sh"
    runnable.container.commands = ["-c", "echo Hello world! This is task ${BATCH_TASK_INDEX}. This job has a total of ${BATCH_TASK_COUNT} tasks."]

    # Define what will be done as part of the job.
    task = batch_v1.TaskSpec()
    task.runnables = [runnable]

    # We can specify what resources are requested by each task.
    resources = batch_v1.ComputeResource()
    resources.cpu_milli = 1000  # in milliseconds per cpu-second. This means the task requires 2 whole CPUs.
    resources.memory_mib = 512
    task.compute_resource = resources

    task.max_retry_count = 2
    task.max_run_duration = "3600s"

    # Tasks are grouped inside a job using TaskGroups.
    # Currently, it's possible to have only one task group.
    group = batch_v1.TaskGroup()
    group.task_count = 1
    group.task_spec = task

    # Policies are used to define on what kind of virtual machines the tasks will run on.
    # In this case, we tell the system to use "e2-standard-4" machine type.
    # Read more about machine types here: https://cloud.google.com/compute/docs/machine-types
    policy = batch_v1.AllocationPolicy.InstancePolicy()
    policy.machine_type = "n1-standard-2"
    # policy.machine_type = machine
    instances = batch_v1.AllocationPolicy.InstancePolicyOrTemplate()
    instances.policy = policy

    location_policy = batch_v1.AllocationPolicy.LocationPolicy()
    location_policy.allowed_locations = [f"regions/{region}"]

    # Set Network
    network_interface = batch_v1.AllocationPolicy.NetworkInterface()
    netwotk_id = f"projects/{project_id}/global/networks/{network}"
    subnetwork_id = f"projects/{project_id}/regions/{region}/subnetworks/{subnet}"
    print(f"Using network_id={netwotk_id}")
    print(f"Using subnetwork_id={subnetwork_id}")
    network_interface.network = netwotk_id
    network_interface.subnetwork = subnetwork_id
    # network_interface.no_external_ip_address = True

    network_policy = batch_v1.AllocationPolicy.NetworkPolicy()
    network_policy.network_interfaces = [network_interface]

    service_account = batch_v1.types.ServiceAccount()
    service_account.email = service_account_email
    print(f"Using service account {service_account_email}")

    allocation_policy = batch_v1.AllocationPolicy()
    allocation_policy.instances = [instances]
    allocation_policy.location = location_policy
    allocation_policy.network = network_policy
    allocation_policy.service_account = service_account

    job = batch_v1.Job()
    job.task_groups = [group]
    job.allocation_policy = allocation_policy
    # job.labels = {"env": "testing", "type": "script"}
    # We use Cloud Logging as it's an out of the box available option
    job.logs_policy = batch_v1.LogsPolicy()
    job.logs_policy.destination = batch_v1.LogsPolicy.Destination.CLOUD_LOGGING

    create_request = batch_v1.CreateJobRequest()
    create_request.job = job
    job_name = f"{job_name}-{uuid.uuid4().hex}"
    create_request.job_id = job_name
    # The job's parent is the region in which the job will run
    create_request.parent = f"projects/{project_id}/locations/{region}"

    print(f"Submitting {job_name} to run script on input data inside gs://{bucket}")
    return client.create_job(create_request)
    # [END batch_create_script_job]
