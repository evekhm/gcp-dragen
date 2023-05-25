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
import json
import os
import uuid
import datetime
from google.cloud import batch_v1
from google.cloud import secretmanager

## Config
# "imageUri": "us-docker.pkg.dev/jarvice/images/illumina-dragen:$version",

# imageUri = "gcr.io/google-containers/busybox"
# entrypoint": "/bin/sh"
# command = "echo Hello world! This is task ${BATCH_TASK_INDEX}. This job has a total of ${BATCH_TASK_COUNT} tasks."

entrypoint = "/bin/bash"
date_str = datetime.datetime.now().strftime('%Y-%m-%d-%H-%M-%S')

def run_job(event, context):
    event_id  = datetime.datetime.utcnow().strftime('%Y-%m-%d-%H-%M-%S')
    project_id = os.environ.get("GCP_PROJECT",
                                 os.environ.get("PROJECT_ID", ""))
    region = os.getenv('GCLOUD_REGION', "us-central1")
    job_name = os.getenv('JOB_NAME_SHORT', "dragen-job")
    network = os.getenv('GCLOUD_NETWORK', "default")
    subnet = os.getenv('GCLOUD_SUBNET', "default")
    jxe_app = os.getenv('JXE_APP')
    image_uri = os.getenv('IMAGE_URI')
    trigger_file_name = os.getenv('TRIGGER_FILE_NAME', "START_PIPELINE")
    licence_secret = os.getenv('LICENCE_SECRET')
    s3_secret_name = os.getenv('S3_SECRET')
    service_account_email = os.getenv('JOB_SERVICE_ACCOUNT')
    machine = os.getenv('GCLOUD_MACHINE', "n1-standard-2")
    print(f"{event_id} Using PROJECT_ID = {project_id}, region = {region},"
          f" job_name = {job_name}, network = {network},"
          f" subnet = {subnet}, "
          f" s3_secret_name = {s3_secret_name}, "
          f"service_account_email = {service_account_email},"
          f" machine = {machine}")

    print(event)
    bucket = None
    file_path = None
    if 'bucket' in event:
        bucket = event['bucket']

    if "name" in event:
        file_path = event['name']

    assert bucket, "Bucket unknown"
    assert file_path, "Filename unknown"
    assert jxe_app, "JXE_APP unknown"
    assert licence_secret, "LICENCE_SECRET unknown"

    # file=inputs/START_PIPELINE
    # bucket
    print(f"{event_id} - Received GCS finalized event on bucket={bucket}, file_path={file_path} ")
    filename = os.path.basename(file_path)

    if filename != trigger_file_name:
      print(f"{event_id} - Skipping action, since waiting for {trigger_file_name} to trigger pipe-line")
      return

    dirs = os.path.dirname(file_path)
    if dirs == "":
      input_path = f"s3://{bucket}"
    else:
      input_path = f"s3://{bucket}/{dirs}"
    print(f"{event_id} - Triggering pipeline for input path = {input_path}")

    s3_secret_value = get_secret_value(s3_secret_name, project_id)
    assert s3_secret_value, "Could not retrieve S3_SECRET name"
    print(f"s3_secret_value={s3_secret_value}")
    access_key = s3_secret_value["access_key"]
    access_secret = s3_secret_value["access_secret"]
    assert access_key, "Could not retrieve access_key for input bucket"
    assert access_secret, "Could not retrieve access_secret for input bucket"
    print(f"access_key={access_key}, access_secret={access_secret}")

    licesne_values = get_secret_value(licence_secret, project_id)
    assert licesne_values, f"Could not retrieve {licence_secret} name"
    print(f"licence_secret={licence_secret}")
    jxe_username = licesne_values["jxe_username"]
    jxe_apikey = licesne_values["jxe_apikey"]
    illumina_license = licesne_values["illumina_license"]

    assert jxe_username, "Could not retrieve jxe_username "
    assert jxe_apikey, "Could not retrieve jxe_apikey"
    assert illumina_license, "Could not retrieve illumina_license"
    print(f"access_key={access_key}, access_secret={access_secret}")

    command = f"jarvice-dragen-stub.sh " \
              f"--project {project_id} " \
              f"--network {network} " \
              f"--subnet {subnet} " \
              f"--username {jxe_username} " \
              f"--apikey {jxe_apikey} " \
              f"--dragen-app {jxe_app} " \
              f"--s3-access-key {access_key} " \
              f"--s3-secret-key {access_secret} " \
              f"-- " \
              f"-f " \
              f"-1 {input_path}/inputs/HG002.novaseq.pcr-free.35x.R1.fastq.ora " \
              f"-2 {input_path}/inputs/HG002.novaseq.pcr-free.35x.R2.fastq.ora " \
              f"--RGID HG002 " \
              f"--RGSM HG002 " \
              f"--ora-reference {input_path}/references/lenadata " \
              f"-r {input_path}/references/hg38_alt_masked_cnv_graph_hla_rna-8-r2.0-1 " \
              f"--enable-map-align true " \
              f"--enable-map-align-output true " \
              f"--enable-duplicate-marking true " \
              f"--output-format CRAM " \
              f"--enable-variant-caller true " \
              f"--enable-vcf-compression true " \
              f"--vc-emit-ref-confidence GVCF " \
              f"--vc-enable-vcf-output true " \
              f"--enable-cnv true " \
              f"--cnv-enable-self-normalization true " \
              f"--cnv-segmentation-mode slm " \
              f"--enable-cyp2d6 true " \
              f"--enable-cyp2b6 true " \
              f"--enable-gba true " \
              f"--enable-smn true " \
              f"--enable-star-allele true " \
              f"--enable-sv true " \
              f"--repeat-genotype-enable true " \
              f"--repeat-genotype-use-catalog expanded " \
              f"--output-file-prefix HG002_pure " \
              f"--output-directory {input_path}/output/{date_str} " \
              f"--intermediate-results-dir /tmp/whole_genome/temp " \
              f"--logging-to-output-dir true " \
              f"--syslogging-to-output-dir true " \
              f"--lic-server https://{illumina_license}@license.edicogenome.com"


    return create_script_job(project_id=project_id, region=region,
                             job_name=job_name, network=network, subnet=subnet,
                             bucket=bucket,
                             service_account_email=service_account_email,
                             machine=machine, command=command, image_uri=image_uri)


client = secretmanager.SecretManagerServiceClient()


def get_secret_value(secret_name, project_id):
    secret_path = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
    print(f"Getting secret for {secret_path}")
    response = client.access_secret_version(request={"name": secret_path})
    payload = response.payload.data.decode("UTF-8")
    print(f"payload={payload}")
    return json.loads(payload)


def create_script_job(project_id: str, region: str, network: str,
    subnet: str, job_name: str, bucket: str, service_account_email: str,
    machine: str, image_uri: str,  command: str) -> batch_v1.Job:
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
    runnable.container.image_uri = image_uri
    runnable.container.entrypoint = entrypoint
    runnable.container.commands = ["-c", command]

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
    # policy.machine_type = "n1-standard-2"
    policy.machine_type = machine
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


if __name__ == "__main__":
  run_job({'bucket': 'illumina-dragen-sample-data',
           'name': 'test/START_PIPELINE', }, None)