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
import json
import os
import sys
import uuid
from google.cloud import batch_v1
from google.cloud import secretmanager
from google.cloud import storage
from datetime import datetime
from collections.abc import Iterable
from google.cloud.batch_v1.types import JobStatus

# API clients
gcs = storage.Client()  # cloud storage
sm = None  # secret_manager
batch = None  # batch job client

PROJECT_ID = os.getenv("GCP_PROJECT",
                       os.environ.get("PROJECT_ID", ""))
REGION = os.getenv('GCLOUD_REGION', "us-central1")
JOB_NAME = os.getenv('JOB_NAME_SHORT', "dragen-job")
NETWORK = os.getenv('GCLOUD_NETWORK', "default")
SUBNET = os.getenv('GCLOUD_SUBNET', "default")
MACHINE = os.getenv('GCLOUD_MACHINE', "n1-standard-2")
TRIGGER_FILE_NAME = os.getenv('TRIGGER_FILE_NAME', "START_PIPELINE")
SERVICE_ACCOUNT_EMAIL = os.getenv('JOB_SERVICE_ACCOUNT', f"illumina-script-sa@{PROJECT_ID}.iam.gserviceaccount.com")
LICENCE_SECRET = os.getenv('LICENSE_SECRET', "license_secret_key")
S3_SECRET_NAME = os.getenv('S3_SECRET', "s3_hmac_secret_key")
IMAGE_URI_DEFAULT = os.getenv('IMAGE_URI', "us-docker.pkg.dev/jarvice/images/illumina-dragen:dev")


def load_config(bucketname, file_path):
    print(f"load_config with bucket={bucketname}, file_path={file_path}")
    file_name = os.path.basename(file_path)

    try:
        if bucketname and gcs.get_bucket(bucketname).exists():
            buc = gcs.get_bucket(bucketname)
            blob = buc.blob(file_path)
            if blob.exists():
                print(f"======== loading configuration from {file_path}...")
                data = json.loads(blob.download_as_text(encoding="utf-8"))
                return data
            else:
                print(
                    f"Warning: file_path = {file_path} does not exist inside {bucketname}. ")
                if file_path != os.path.basename(file_path):
                    dir_path = "/".join(os.path.dirname(file_path).split("/")[:-1])
                    print(
                        f"Checking if {file_name} exists in the top level folder {dir_path}.")
                    if dir_path == "":
                        file_path = file_name
                    else:
                        file_path = f"{dir_path}/{file_name}"
                    return load_config(bucketname, file_path)
                else:
                    print(f"Error: file does not exist")

        else:
            print(f"Error: bucket does not exist {bucketname}")
    except Exception as e:
        print(
            f"Error: while obtaining file from GCS gs://{bucketname}/{file_path} {e}")
    return {}


def run_dragen_job(event, context):
    print(event)
    bucket = None
    file_path = None
    if 'bucket' in event:
        bucket = event['bucket']

    if "name" in event:
        file_path = event['name']

    assert bucket, "Bucket unknown where to run pipeline"
    assert file_path, "Filename unknown"

    print(f"Using PROJECT_ID = {PROJECT_ID}, region = {REGION},"
          f" job_name = {JOB_NAME}, network = {NETWORK},"
          f" subnet = {SUBNET}, "
          f"service_account_email = {SERVICE_ACCOUNT_EMAIL},"
          f" machine = {MACHINE}")

    # file=inputs/START_PIPELINE
    # bucket
    print(
        f"Received GCS finalized event on bucket={bucket}, file_path={file_path} ")
    filename = os.path.basename(file_path)

    if filename != TRIGGER_FILE_NAME:
        print(
            f"Skipping action on {filename}, since waiting for {TRIGGER_FILE_NAME} to trigger pipe-line")
        return

    dirs = os.path.dirname(file_path)
    if dirs == "":
        input_path = f"s3://{bucket}"
    else:
        input_path = f"s3://{bucket}/{dirs}"
    print(f"Using data from input path = {input_path}")
    prefix = ""
    if dirs is not None and dirs != "":
        prefix = dirs + "/"

    batch_config = load_config(bucketname=bucket, file_path=f"{prefix}batch_config.json")
    batch_options = batch_config.get("batch_options", {})
    if batch_options == {}:
        print(
            f"Error: batch_options could not be retrieved, will be using hard-coded default values.")
    else:
        print(f"batch_options={batch_options}")

    commands = handle_input_files(bucket, prefix)
    return create_script_job(bucket=bucket, batch_options=batch_options, commands=commands)


def get_reference_dir(bucket, prefix):
    blob_list = gcs.list_blobs(bucket, prefix=prefix)
    for blob in blob_list:
        # TODO seems like a missing feature, cannot list subfolders inside a folder
        # Hence a hack below
        split = os.path.dirname(blob.name).split(f"{prefix}")
        if len(split) > 1 and split[1].startswith("hg38"):
            folder = split[1].split("/")[0]
            return folder

    return None


def directory_exists(bucket_name, dir_name):
    if bucket_name:
        gcs_bucket = gcs.get_bucket(bucket_name)
        print(f"eee {gcs_bucket}")
        return gcs_bucket.exists(dir_name)
    return False


def get_input_files(bucket_name, dir_name):
    print(f"bucket_name={bucket_name}, dir_name={dir_name}")
    cram_files_dict = {}
    ora_dir_dict = {}
    #for b in gcs.list_blobs(bucket_name, prefix=f"{dir_name}", delimiter="/"):
    for b in gcs.list_blobs(bucket_name, prefix=f"{dir_name}"):

        dir_path_name = "/".join(b.name.split("/")[:-1])
        if b.name.lower().endswith(".ora"):
            # ora files in same folder => should be grouped to be filled in as single command. Other directories - could be processed grouped in parallel

            if dir_path_name not in ora_dir_dict:
                ora_dir_dict[dir_path_name] = []
            ora_dir_dict[dir_path_name].append(b.name)

        elif b.name.lower().endswith(".cram"):
            if dir_path_name not in ora_dir_dict:
                cram_files_dict[dir_path_name] = []
            cram_files_dict[dir_path_name].append(b.name)

    assert len(ora_dir_dict) != 0 or len(cram_files_dict) != 0, f"No ora/cram files detected inside {bucket_name}/{dir_name}"

    return ora_dir_dict, cram_files_dict


def find_file(bucket, prefix, name_filter):
    blob_list = gcs.list_blobs(bucket, prefix=f"{prefix}")
    print(f"Using bucket={bucket} prefix={prefix}")
    files = [(blob.name, blob.updated.strftime("%Y-%m-%d %H:%M:%S.%f"))
             for blob in blob_list if name_filter(blob.name)]

    files.sort(
        key=lambda date: datetime.strptime(date[1], "%Y-%m-%d %H:%M:%S.%f"))
    if len(files) == 0:
        return None

    if len(files) > 1:
        print(f"Taking most recently updated file (multiple detected {files})")
        return files[-1][0]

    return files[0][0]


# path can be 'empty' or "/something
def get_command(bucket, prefix, dragen_options, jarvice_options, inputs, output_file_prefix=None):
    print(f"get_command - prefix={prefix}")
    print(f"Using PROJECT_ID = {PROJECT_ID}, region = {REGION},"
          f" job_name = {JOB_NAME}, network = {NETWORK},"
          f" subnet = {SUBNET}, "
          f" s3_secret_name = {S3_SECRET_NAME}, "
          f"service_account_email = {SERVICE_ACCOUNT_EMAIL},"
          f" machine = {MACHINE}")

    jxe_app = jarvice_options.get('jxe_app',
                                  'illumina-dragen_4_0_3_13_g52a8599a')

    s3_secret_value = get_secret_value(S3_SECRET_NAME, PROJECT_ID)

    print(f"s3_secret_value={s3_secret_value}")
    access_key = s3_secret_value["access_key"]
    access_secret = s3_secret_value["access_secret"]

    print(f"access_key={access_key}, access_secret={access_secret}")

    licesne_values = get_secret_value(LICENCE_SECRET, PROJECT_ID)

    print(f"licence_secret={LICENCE_SECRET}")
    jxe_username = licesne_values["jxe_username"]
    jxe_apikey = licesne_values["jxe_apikey"]
    illumina_license = licesne_values["illumina_license"]

    assert LICENCE_SECRET, "LICENSE_SECRET unknown"
    assert s3_secret_value, "Could not retrieve S3_SECRET name"
    assert licesne_values, f"Could not retrieve {LICENCE_SECRET} name"
    assert access_key, "Could not retrieve access_key for input bucket"
    assert access_secret, "Could not retrieve access_secret for input bucket"
    assert jxe_username, "Could not retrieve jxe_username "
    assert jxe_apikey, "Could not retrieve jxe_apikey"
    assert illumina_license, "Could not retrieve illumina_license"
    print(f"access_key={access_key}, access_secret={access_secret}")

    date_str = datetime.now().strftime('%Y-%m-%d-%H-%M-%S')
    output_default = f"s3://{bucket}/output"

    lenadata_path = dragen_options.get('ora-reference',
                                       f"s3://{bucket}/references/lenadata")
    reference_path = dragen_options.get('reference',
                                        f"s3://{bucket}/references/hg38_alt_masked_cnv_graph_hla_rna-8-r2.0-1")

    if output_file_prefix is None:
        output_file_prefix = dragen_options.get('output-file-prefix', 'HG002_pure')
    print(
        f"inputs={inputs}, reference_path={reference_path}, lenadata_path={lenadata_path}")
    command = f"jarvice-dragen-stub.sh " \
              f"--project {PROJECT_ID} " \
              f"--network {NETWORK} " \
              f"--subnet {SUBNET} " \
              f"--username {jxe_username} " \
              f"--apikey {jxe_apikey} " \
              f"--dragen-app {jxe_app} " \
              f"--s3-access-key {access_key} " \
              f"--s3-secret-key {access_secret} " \
              f"-- " \
              f"-f {inputs}" \
              f"--RGID {dragen_options.get('RGID', 'HG002')} " \
              f"--RGSM {dragen_options.get('RGSM', 'HG002')} " \
              f"--ora-reference {lenadata_path} " \
              f"-r {reference_path} " \
              f"--enable-map-align {dragen_options.get('enable-map-align', 'true')} " \
              f"--enable-map-align-output {dragen_options.get('enable-map-align-output', 'true')} " \
              f"--enable-duplicate-marking {dragen_options.get('enable-duplicate-marking', 'true')} " \
              f"--output-format  {dragen_options.get('output-format', 'CRAM')} " \
              f"--enable-variant-caller {dragen_options.get('enable-variant-caller', 'true')} " \
              f"--enable-vcf-compression {dragen_options.get('enable-vcf-compression', 'true')} " \
              f"--vc-emit-ref-confidence {dragen_options.get('vc-emit-ref-confidence', 'GVCF')} " \
              f"--vc-enable-vcf-output {dragen_options.get('vc-enable-vcf-output', 'true')} " \
              f"--enable-cnv  {dragen_options.get('enable-cnv', 'true')} " \
              f"--cnv-enable-self-normalization {dragen_options.get('cnv-enable-self-normalization', 'true')} " \
              f"--cnv-segmentation-mode  {dragen_options.get('cnv-segmentation-mode', 'slm')} " \
              f"--enable-cyp2d6 {dragen_options.get('enable-cyp2d6', 'true')} " \
              f"--enable-cyp2b6 {dragen_options.get('enable-cyp2b6', 'true')} " \
              f"--enable-gba {dragen_options.get('enable-gba', 'true')} " \
              f"--enable-smn {dragen_options.get('enable-smn', 'true')} " \
              f"--enable-star-allele {dragen_options.get('enable-star-allele', 'true')} " \
              f"--enable-sv {dragen_options.get('enable-sv', 'true')} " \
              f"--repeat-genotype-enable {dragen_options.get('repeat-genotype-enable', 'true')} " \
              f"--repeat-genotype-use-catalog  {dragen_options.get('repeat-genotype-use-catalog', 'expanded')} " \
              f"--output-file-prefix  {output_file_prefix} " \
              f"--output-directory  {dragen_options.get('output-directory', output_default)}/{prefix}{date_str} " \
              f"--intermediate-results-dir {dragen_options.get('intermediate-results-dir', '/tmp/whole_genome/temp')} " \
              f"--logging-to-output-dir {dragen_options.get('logging-to-output-dir', 'true')} " \
              f"--syslogging-to-output-dir {dragen_options.get('syslogging-to-output-dir', 'true')} " \
              f"--lic-server https://{illumina_license}@license.edicogenome.com"
    print(command)
    return command


def list_jobs() -> Iterable[batch_v1.Job]:
    """
    Get a list of all jobs defined in given region.

    Args:
        project_id: project ID or project number of the Cloud project you want to use.
        region: name of the region hosting the jobs.

    Returns:
        An iterable collection of Job object.
    """
    client = batch_v1.BatchServiceClient()

    jobs = client.list_jobs(parent=f"projects/{PROJECT_ID}/locations/{REGION}")

    running_jobs_count = 0
    queued_jobs_count = 0
    for job in jobs:
        state = job.status.state
        if state == JobStatus.State.RUNNING:
            running_jobs_count += 1
        elif state == JobStatus.State.QUEUED:
            queued_jobs_count += 1
        elif state == JobStatus.State.SCHEDULED:
            queued_jobs_count += 1

    return jobs


def get_secret_value(secret_name, project_id):
    global sm
    if not sm:
        sm = secretmanager.SecretManagerServiceClient()

    secret_path = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
    print(f"Getting secret for {secret_path}")
    response = sm.access_secret_version(request={"name": secret_path})
    payload = response.payload.data.decode("UTF-8")
    print(f"payload={payload}")
    return json.loads(payload)


def get_options(bucket, prefix):
    config = load_config(bucketname=bucket, file_path=f"{prefix}config.json")

    dragen_options = config.get("dragen_options", {})
    if dragen_options == {}:
        print(
            f"Error: dragen_options could not be retrieved, will be using hard-coded default values.")
    else:
        print(f"dragen_options={dragen_options}")
    jarvice_options = config.get("jarvice_options", {})
    if jarvice_options == {}:
        print(
            f"Error: jarvice_options could not be retrieved, will be using hard-coded default values.")
    else:
        print(f"jarvice_options={jarvice_options}")
    return dragen_options, jarvice_options


def handle_input_files(bucket: str, prefix: str):
    ora_files_dic, cram_files_dic = get_input_files(bucket_name=bucket, dir_name=prefix)

    commands = []
    # ora files - combine all inputs in one command
    for prefix in ora_files_dic:
        group = ora_files_dic[prefix]
        if prefix != "":
            prefix = prefix + "/"

        # config.json using prefix
        dragen_options, jarvice_options = get_options(bucket, prefix)
        image_uri = jarvice_options.get('image_uri', IMAGE_URI_DEFAULT)
        entrypoint = jarvice_options.get('entrypoint', '/bin/bash')
        print(f"======== handling input ORA files group {', '.join(group)} ")
        inputs = ""
        for index, input_file in enumerate(group):
            inputs = inputs + f" -{index + 1} s3://{bucket}/{input_file} "
        command = get_command(bucket=bucket, prefix=prefix, dragen_options=dragen_options,
                              jarvice_options=jarvice_options, inputs=inputs)
        commands.append((image_uri, entrypoint, command))

    # cram files - same folder - different commands
    for prefix in cram_files_dic:
        # config.json using prefix
        group = cram_files_dic[prefix]
        if prefix != "":
            prefix = prefix + "/"
        # config.json using prefix
        dragen_options, jarvice_options = get_options(bucket, prefix)
        image_uri = jarvice_options.get('image_uri', IMAGE_URI_DEFAULT)
        entrypoint = jarvice_options.get('entrypoint', '/bin/bash')
        for f in group:
            prefix = f"{prefix}{os.path.basename(f)}/"
            # create a task
            print(f"======== handling input CRAM files  {f}")
            inputs = f" --cram-input s3://{bucket}/{f} "
            command = get_command(bucket=bucket, prefix=prefix, dragen_options=dragen_options,
                                  jarvice_options=jarvice_options, inputs=inputs, output_file_prefix=os.path.splitext(os.path.basename(f))[0])
            commands.append((image_uri, entrypoint, command))

    return commands


def create_script_job(bucket: str, batch_options, commands) -> batch_v1.Job:
    """
      This method shows how to create a sample Batch Job that will run
      a simple command on Cloud Compute instances.

      Returns:
          A job object representing the job created.
      """

    # We can specify what resources are requested by each task.
    resources = batch_v1.ComputeResource()
    resources.cpu_milli = 1000  # in milliseconds per cpu-second. This means the task requires 2 whole CPUs.
    resources.memory_mib = 512

    # Tasks are grouped inside a job using TaskGroups.
    # Currently, it's possible to have only one task group.
    group = batch_v1.TaskGroup()
    task_count = min(len(commands), batch_options.get('ora-task_count', 10))
    parallelism = batch_options.get('parallelism', 3)

    print(f"======== Using Job task_count = {task_count} and parallelism = {parallelism} ========")
    group.task_count = task_count
    group.parallelism = parallelism

    # Policies are used to define on what kind of virtual machines the tasks will run on.
    # In this case, we tell the system to use "e2-standard-4" machine type.
    # Read more about machine types here: https://cloud.google.com/compute/docs/machine-types
    policy = batch_v1.AllocationPolicy.InstancePolicy()
    # policy.machine_type = "n1-standard-2"
    policy.machine_type = MACHINE
    instances = batch_v1.AllocationPolicy.InstancePolicyOrTemplate()
    instances.policy = policy

    location_policy = batch_v1.AllocationPolicy.LocationPolicy()
    location_policy.allowed_locations = [f"regions/{REGION}"]

    # Set Network
    network_interface = batch_v1.AllocationPolicy.NetworkInterface()
    netwotk_id = f"projects/{PROJECT_ID}/global/networks/{NETWORK}"
    subnetwork_id = f"projects/{PROJECT_ID}/regions/{REGION}/subnetworks/{SUBNET}"
    print(f"Using network_id={netwotk_id}")
    print(f"Using subnetwork_id={subnetwork_id}")
    network_interface.network = netwotk_id
    network_interface.subnetwork = subnetwork_id
    # network_interface.no_external_ip_address = True

    network_policy = batch_v1.AllocationPolicy.NetworkPolicy()
    network_policy.network_interfaces = [network_interface]

    service_account = batch_v1.types.ServiceAccount()
    service_account.email = SERVICE_ACCOUNT_EMAIL
    print(f"Using service account {SERVICE_ACCOUNT_EMAIL}")

    allocation_policy = batch_v1.AllocationPolicy()
    allocation_policy.instances = [instances]
    allocation_policy.location = location_policy
    allocation_policy.network = network_policy
    allocation_policy.service_account = service_account

    runnables = []
    for (image_uri, entrypoint, command) in commands:
        # Define what will be done as part of the job.
        runnable = batch_v1.Runnable()
        runnable.container = batch_v1.Runnable.Container()
        runnable.container.image_uri = image_uri
        runnable.container.entrypoint = entrypoint
        runnable.container.commands = ["-c", command]
        runnables.append(runnable)

    # Define what will be done as part of the job.
    task = batch_v1.TaskSpec()
    task.compute_resource = resources

    task.max_retry_count = batch_options.get('max_retry_count', 2)
    task.max_run_duration = batch_options.get('max_run_duration', "3600s")
    task.runnables = runnables

    group.task_spec = task

    job = batch_v1.Job()
    job.task_groups = [group]
    job.allocation_policy = allocation_policy
    # job.labels = {"env": "testing", "type": "script"}
    # We use Cloud Logging as it's an out of the box available option
    job.logs_policy = batch_v1.LogsPolicy()
    job.logs_policy.destination = batch_v1.LogsPolicy.Destination.CLOUD_LOGGING

    create_request = batch_v1.CreateJobRequest()
    create_request.job = job
    job_name = f"{JOB_NAME}-{uuid.uuid4().hex}"
    create_request.job_id = job_name
    # The job's parent is the region in which the job will run
    create_request.parent = f"projects/{PROJECT_ID}/locations/{REGION}"

    print(
        f"Submitting {job_name} to run script on input data inside gs://{bucket}")

    global batch
    if not batch:
        batch = batch_v1.BatchServiceClient()

    return batch.create_job(create_request)

    # [END batch_create_script_job]


if __name__ == "__main__":
    # list_jobs()

    name = "START_PIPELINE"
    if len(sys.argv) > 1:
        name = f"{sys.argv[1]}/START_PIPELINE"

    bucket = f'{PROJECT_ID}-input'
    print(f"Using file_name={name}, bucket={bucket}")
    run_dragen_job({'bucket': bucket,
                    'name': name, }, None)
