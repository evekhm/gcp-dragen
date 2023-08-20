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

import argparse
import datetime
import json
import os
import uuid

from google.cloud import batch_v1
from google.cloud import bigquery
from google.cloud import secretmanager
from google.cloud import storage
from google.cloud.batch_v1.types import JobStatus

import helper
from logging_handler import Logger

CRAM_INPUT = "cram"
FASTQ_LIST_INPUT = "fastq-list"
FASTQ_INPUT = "fastq"
SAMPLE_ID = "SAMPLE_ID"
INPUT_PATH = "INPUT_PATH"
OUTPUT_PATH = "OUTPUT_PATH"
# API clients
gcs = storage.Client()  # cloud storage
sm = None  # secret_manager
batch = None  # batch job client

PROJECT_ID = os.getenv("GCP_PROJECT", os.environ.get("PROJECT_ID", ""))
REGION = os.getenv('GCLOUD_REGION', "us-central1")
JOB_NAME = os.getenv('JOB_NAME_SHORT', "job-dragen")
NETWORK = os.getenv('GCLOUD_NETWORK', "default")
SUBNET = os.getenv('GCLOUD_SUBNET', "default")
MACHINE = os.getenv('GCLOUD_MACHINE', "n1-standard-2")
TRIGGER_FILE_NAME = os.getenv('TRIGGER_FILE_NAME', "START_PIPELINE")
SERVICE_ACCOUNT_EMAIL = os.getenv('JOB_SERVICE_ACCOUNT', f"illumina-script-sa@{PROJECT_ID}.iam.gserviceaccount.com")
LICENCE_SECRET = os.getenv('LICENSE_SECRET', "license_secret_key")
S3_SECRET_NAME = os.getenv('S3_SECRET', "s3_hmac_secret_key")
IMAGE_URI_DEFAULT = os.getenv('IMAGE_URI', "us-docker.pkg.dev/jarvice/images/illumina-dragen:dev")
PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE = os.getenv('PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE',
                                                 "job-dragen-task-state-change-topic")
BIGQUERY_DB = os.getenv('BIGQUERY_DB', "dragen_illumina.samples_status")
assert BIGQUERY_DB, "BIGQUERY_DB is not set"

bigquery_client = bigquery.Client()


def load_config(bucketname, file_path, recursive_find=False):
    Logger.info(f"load_config with bucket={bucketname}, file_path={file_path}")
    file_name = os.path.basename(file_path)

    try:
        if bucketname and gcs.get_bucket(bucketname).exists():
            buc = gcs.get_bucket(bucketname)
            blob = buc.blob(file_path)
            if blob.exists():
                Logger.info(f"======== loading configuration from gs://{bucketname}/{file_path}...")
                data = json.loads(blob.download_as_text(encoding="utf-8"))
                return data
            elif recursive_find:
                Logger.warning(
                    f"Warning: file_path = {file_path} does not exist inside {bucketname}. ")
                if file_path != os.path.basename(file_path):
                    dir_path = "/".join(os.path.dirname(file_path).split("/")[:-1])
                    Logger.info(
                        f"Checking if {file_name} exists in the top level folder {dir_path}.")
                    if dir_path == "":
                        file_path = file_name
                    else:
                        file_path = f"{dir_path}/{file_name}"
                    return load_config(bucketname, file_path)
                else:
                    Logger.error(f"Error: file {file_path} does not exist")
            else:
                Logger.error(f"Error: file {file_path} does not exist")

        else:
            Logger.error(f"Error: bucket does not exist {bucketname}")
    except Exception as e:
        Logger.error(
            f"Error: while obtaining file from GCS gs://{bucketname}/{file_path} {e}")
    return {}


def run_dragen_job(event, context):
    Logger.info(event)
    bucket = None
    file_path = None
    if 'bucket' in event:
        bucket = event['bucket']

    if "name" in event:
        file_path = event['name']

    assert bucket, "Bucket unknown where to run pipeline"
    assert file_path, "Filename unknown"

    Logger.info(f"Using PROJECT_ID = {PROJECT_ID}, region = {REGION},"
                f" job_name = {JOB_NAME}, network = {NETWORK},"
                f" subnet = {SUBNET}, "
                f"service_account_email = {SERVICE_ACCOUNT_EMAIL},"
                f" machine = {MACHINE}")

    # file=inputs/START_PIPELINE
    # bucket
    Logger.info(
        f"Received GCS finalized event on bucket={bucket}, file_path={file_path} ")
    filename = os.path.basename(file_path)

    if filename != TRIGGER_FILE_NAME:
        print(
            f"Skipping action on {filename}, since waiting for {TRIGGER_FILE_NAME} to trigger pipe-line")
        return

    dirs = os.path.dirname(file_path)
    prefix = ""
    if dirs is not None and dirs != "":
        prefix = dirs + "/"

    batch_config = load_config(bucketname=bucket, file_path=f"{prefix}batch_config.json")
    if batch_config == {}:
        Logger.error(
            f"Error: batch_options could not be retrieved.")
        return
    else:
        Logger.info(f"batch_options={batch_config}")

    dryrun=False
    run_options = batch_config.get("run_options", {})
    if "dryrun" in run_options:
        dryrun = run_options.get("dryrun")

    output_options = batch_config.get("output_options", {})

    input_option = batch_config.get("input_options", {})
    samples_list = []
    input_type = input_option.get("input_type")

    if input_type.lower() == CRAM_INPUT:
        extension = ".cram"
    elif input_type.lower() == FASTQ_INPUT:
        extension = ".ora"
    else:
        Logger.error(f"Error, unsupported type {input_type}")
        return

    config_path = input_option.get("config", None)
    if config_path:
        config_bucket, config_prefix = helper.split_uri_2_bucket_prefix(config_path)
        config_options = load_config(config_bucket, config_prefix)
        if config_options == {}:
            print(f"Error, could not load configuration options from {config_path}")
            return
    else:
        print(f"Error, config path is not properly specified for the input {input_option}")
        return

    input_list_uri = input_option.get("input_list", None)
    if input_list_uri:
        samples_list.extend(get_samples_list_from_file(input_list_uri))

    input_path = input_option.get("input_path", None)
    if input_path:
        samples_list.extend(get_samples_list_from_path(input_path, extension))

    if len(samples_list) == 0:
        Logger.error(f"Error, no input files detected")
        return

    dragen_options, jarvice_options = get_options(config_options)
    command, env_variables = task_info(dragen_options=dragen_options, jarvice_options=jarvice_options,
                                       samples_list=samples_list, input_type=input_type)

    task_count = None
    for key in env_variables:
        if task_count is not None:
            assert task_count == len(env_variables[key]), f"Env variables not filled in consistently for all tasks" \
                                                          f" {env_variables}"
        else:
            task_count = len(env_variables[key])

    return create_script_job(bucket=bucket, batch_options=run_options,  jarvice_options=jarvice_options,
                             output_options=output_options, input_type=input_type,
                             command=command, dryrun=dryrun, env_variables=env_variables)


def task_info(dragen_options, jarvice_options, samples_list, input_type):
    date_str = datetime.datetime.now().strftime('%Y-%m-%d-%H-%M-%S')
    replace_options = [("<date>", date_str)]
    if input_type == FASTQ_INPUT:
        # fastq files - combine all inputs in one command
        inputs = ""
        f_uris = ""
        env_variables = {}

        for index, (sample, input_file) in enumerate(samples_list):
            inputs = inputs + f" -{index + 1} {input_file} "
            f_uris = f_uris + f" {input_file}"

        env_variables[INPUT_PATH] = [inputs.replace("gs://", "s3://")]
        if "--output-directory" in dragen_options:
            env_variables[OUTPUT_PATH] = [dragen_options.get("--output-directory").replace("<date>", date_str)]

        command, output_path = get_task_command(dragen_options=dragen_options, jarvice_options=jarvice_options,
                                                inputs=inputs, replace_options=replace_options)

        return command, env_variables
        # commands.append((image_uri, entrypoint, command, f",{f_uris}", output_path))
    elif input_type == CRAM_INPUT:
        env_variables = {SAMPLE_ID: [], INPUT_PATH: [], OUTPUT_PATH: []}
        for (sample_id, f_uri) in samples_list:
            env_variables[SAMPLE_ID].append(sample_id)
            env_variables[INPUT_PATH].append(f_uri.replace("gs://", "s3://"))
            if "--output-directory" in dragen_options:
                env_variables[OUTPUT_PATH].append(dragen_options.get("--output-directory").
                                                  replace("${SAMPLE_ID}", sample_id).replace("<date>", date_str))

        inputs = " --cram-input ${INPUT_PATH}"
        command, output_path = get_task_command(dragen_options=dragen_options, jarvice_options=jarvice_options,
                                                inputs=inputs, replace_options=replace_options)

        return command, env_variables

    elif input_type == FASTQ_LIST_INPUT:
        inputs = f" --fastq-list"  # TODO
        Logger.error(f"Method Not implemented yet")
    else:
        Logger.error(f"Error, unsupported input_type {input_type}")

    return None, None


def get_samples_list_from_path(path_uri: str, extension: str):
    Logger.info(f"get_samples_list_from_path - {path_uri}")
    bucket_name, prefix = helper.split_uri_2_bucket_prefix(path_uri)
    if prefix != "":
        prefix = prefix + "/"

    input_list = []  # (sample_name, uri)

    # for b in gcs.list_blobs(bucket_name, prefix=f"{dir_name}", delimiter="/"):
    for b in gcs.list_blobs(bucket_name, prefix=f"{prefix}"):
        if b.name.lower().endswith(extension.lower()):
            sample_name = os.path.splitext(os.path.basename(b.name))[0]
            input_list.append((sample_name, f"s3://{bucket_name}/{b.name}"))

    Logger.info(f"get_samples_list_from_path - input_list={input_list}")
    return input_list


def get_samples_list_from_file(file_uri: str):
    Logger.info(f"get_samples_list_from_file - {file_uri}")
    bucket_name, file_name = helper.split_uri_2_bucket_prefix(file_uri)
    storage_client = storage.Client()
    bucket = storage_client.get_bucket(bucket_name)

    blob = bucket.blob(file_name)
    text = blob.download_as_text().replace('\r', '').replace('\t', ' ')
    lines = text.split('\n')

    input_list = []  # (sample_name, uri)
    line_nr = 0
    for line in lines:
        line_nr += 1
        if line_nr == 1:
            Logger.info(f"get_samples_list_from_file - Skipping first line {line}")
            continue
        sample_path_list = line.split()
        if len(sample_path_list) > 1:
            input_list.append((sample_path_list[0], sample_path_list[1]))
        else:
            Logger.info(
                f"get_samples_list_from_file - Error on line {line_nr}. Expected '[sample_id] [path]' format, got {line}")

    Logger.info(f"get_samples_list_from_file - Read {line_nr} lines from {file_uri}, got input_list={input_list}")
    return input_list


def get_dragen_command(dragen_command_options, replacements=None):
    options = {}
    for field in dragen_command_options:
        value = dragen_command_options[field]
        if replacements:
            for r, s in replacements:
                value = value.replace(r, s)
        options[field] = value
    return options


def get_task_command(dragen_options, jarvice_options, inputs, replace_options):
    Logger.info(f"Using PROJECT_ID = {PROJECT_ID}, region = {REGION},"
                f" job_name = {JOB_NAME}, network = {NETWORK},"
                f" subnet = {SUBNET}, "
                f" s3_secret_name = {S3_SECRET_NAME}, "
                f"service_account_email = {SERVICE_ACCOUNT_EMAIL},"
                f" machine = {MACHINE}")

    jxe_app = jarvice_options.get('jxe_app', 'illumina-dragen_3_7_8n')

    s3_secret_value = get_secret_value(S3_SECRET_NAME, PROJECT_ID)

    Logger.info(f"s3_secret_value={s3_secret_value}")
    access_key = s3_secret_value["access_key"]
    access_secret = s3_secret_value["access_secret"]

    Logger.info(f"access_key={access_key}, access_secret={access_secret}")

    licesne_values = get_secret_value(LICENCE_SECRET, PROJECT_ID)

    Logger.info(f"licence_secret={LICENCE_SECRET}")
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

    dragen_options_replaced = get_dragen_command(dragen_options, replace_options)
    dragen_options_str = ""
    for key in dragen_options_replaced:
        dragen_options_str += f""" {key} {dragen_options_replaced[key]}"""

    output_path = dragen_options_replaced.get("--output-directory", None)

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
              f""" {inputs}""" \
              f""" {dragen_options_str} """ \
              f""" --lic-server https://{illumina_license}@license.edicogenome.com"""
    Logger.info(f"======== {command}")
    return command, output_path


def get_secret_value(secret_name, project_id):
    global sm
    if not sm:
        sm = secretmanager.SecretManagerServiceClient()

    secret_path = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
    Logger.info(f"Getting secret for {secret_path}")
    response = sm.access_secret_version(request={"name": secret_path})
    payload = response.payload.data.decode("UTF-8")
    Logger.info(f"payload={payload}")
    return json.loads(payload)


def get_options(config):
    dragen_options = config.get("dragen_options", {})
    assert dragen_options != {}, "Error: dragen_options could not be retrieved"

    jarvice_options = config.get("jarvice_options", {})
    assert dragen_options != {}, "Error: jarvice_options could not be retrieved"

    return dragen_options, jarvice_options


def create_script_job(bucket: str, batch_options, command, jarvice_options, output_options, env_variables, input_type,
                      dryrun=False):
    """
      This method shows how to create a sample Batch Job that will run
      a simple command on Cloud Compute instances.

      Returns:
          A job object representing the job created.
      """

    image_uri = jarvice_options.get('image_uri', IMAGE_URI_DEFAULT)
    entrypoint = jarvice_options.get('entrypoint', '/bin/bash')

    # We can specify what resources are requested by each task.
    resources = batch_v1.ComputeResource()
    resources.cpu_milli = batch_options.get("cpu_milli", 1000)  # in milliseconds per cpu-second. This means the task requires 2 whole CPUs.
    resources.memory_mib = batch_options.get("memory_mib", 512)

    # Tasks are grouped inside a job using TaskGroups.
    # Currently, it's possible to have only one task group.
    group = batch_v1.TaskGroup()
    parallelism = batch_options.get('parallelism', 3)

    task_count = len(env_variables[list(env_variables.keys())[0]])
    Logger.info(f"======== Creating job with {task_count} tasks and {parallelism} to be run in parallel ========")

    task_environments = []
    if len(env_variables) > 0:
        for index in range(task_count):
            env_dict = {}
            for key in env_variables:
                env_dict[key] = env_variables[key][index]
            task_environments.append(batch_v1.Environment(variables=env_dict))

    group.parallelism = parallelism
    group.task_environments = task_environments

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
    Logger.info(f"Using network_id={netwotk_id}")
    Logger.info(f"Using subnetwork_id={subnetwork_id}")
    network_interface.network = netwotk_id
    network_interface.subnetwork = subnetwork_id
    # network_interface.no_external_ip_address = True

    network_policy = batch_v1.AllocationPolicy.NetworkPolicy()
    network_policy.network_interfaces = [network_interface]

    service_account = batch_v1.types.ServiceAccount()
    service_account.email = SERVICE_ACCOUNT_EMAIL
    Logger.info(f"Using service account {SERVICE_ACCOUNT_EMAIL}")

    allocation_policy = batch_v1.AllocationPolicy()
    allocation_policy.instances = [instances]
    allocation_policy.location = location_policy
    allocation_policy.network = network_policy
    allocation_policy.service_account = service_account

    notification = batch_v1.JobNotification()
    notification.pubsub_topic = f"projects/{PROJECT_ID}/topics/{PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE}"
    message = batch_v1.JobNotification.Message()
    message.type_ = notification.Type.TASK_STATE_CHANGED
    notification.message = message

    job_name = f"{JOB_NAME}-{uuid.uuid4().hex}"
    # Define what will be done as part of the job.
    runnable = batch_v1.Runnable()
    runnable.container = batch_v1.Runnable.Container()

    if dryrun:
        runnable.container.image_uri = "gcr.io/google-containers/busybox"
        runnable.container.entrypoint = "/bin/sh"
        runnable.container.commands = [
            "-c",
            f"echo Command Line: {command}",
        ]
    else:
        runnable.container.image_uri = image_uri
        runnable.container.entrypoint = entrypoint
        runnable.container.commands = ["-c", command]

    # Define what will be done as part of the job.
    task = batch_v1.TaskSpec()
    task.compute_resource = resources

    task.max_retry_count = batch_options.get('max_retry_count', 2)
    task.max_run_duration = batch_options.get('max_run_duration', "7200s")
    task.runnables = [runnable]

    group.task_spec = task

    job = batch_v1.Job()
    job.task_groups = [group]
    job.allocation_policy = allocation_policy
    job.notifications = [notification]
    # job.labels = {"env": "testing", "type": "script"}
    # We use Cloud Logging as it's an out of the box available option
    job.logs_policy = batch_v1.LogsPolicy()
    job.logs_policy.destination = batch_v1.LogsPolicy.Destination.CLOUD_LOGGING

    create_request = batch_v1.CreateJobRequest()
    create_request.job = job

    create_request.job_id = job_name
    # The job's parent is the region in which the job will run
    create_request.parent = f"projects/{PROJECT_ID}/locations/{REGION}"

    Logger.info(
        f"Submitting {job_name} to run script on input data inside gs://{bucket}")

    global batch
    if not batch:
        batch = batch_v1.BatchServiceClient()

    event_timestamp = datetime.datetime.now(datetime.timezone.utc)
    created_job = batch.create_job(create_request)
    path_to_dir = output_options.get("jobs_created", None)
    for i in range(task_count):
        sample_id = None
        input_path = None
        output_path = None
        if SAMPLE_ID in env_variables:
            sample_id = env_variables[SAMPLE_ID][i]

        if INPUT_PATH in env_variables:
            input_path = env_variables[INPUT_PATH][i]

        if OUTPUT_PATH in env_variables:
            output_path = env_variables[OUTPUT_PATH][i]
        stream_data_to_bq(created_job.uid, sample_id, event_timestamp, command, input_path, input_type, output_path,
                          i, task_environments)

    if path_to_dir:
        write_job_csv(path_to_dir, created_job, command, task_environments)


def stream_data_to_bq(job_id, sample_id, event_timestamp, command, input_path, input_type, output_path, index, task_environments):
    now = datetime.datetime.now(datetime.timezone.utc)
    command = helper.obscure_sensitive_info(command)
    errors = helper.stream_document_to_bigquery([
        {
            "job_id": job_id,
            "task_id": "",
            "sample_id": sample_id,
            "status": "CREATED",
            "event_timestamp": event_timestamp.strftime('%Y-%m-%d %H:%M:%S.%f'),
            "input_type": input_type,
            "input_path": input_path,
            "output_path": magic_replace(output_path, index, task_environments),
            "command": magic_replace(command, index, task_environments),
            "timestamp": now.strftime('%Y-%m-%d %H:%M:%S.%f')
        }

    ])
    if not errors:
        Logger.info(f"New rows have been added for "
                    f"job_id {job_id} ")
    elif isinstance(errors, list):
        error = errors[0].get("errors")
        Logger.error(f"Encountered errors while inserting rows "
                     f"for job_id {job_id} : {error}")


def magic_replace(input_str, batch_task_index, task_environments):
    input_str = input_str.replace("${BATCH_TASK_INDEX}", str(batch_task_index)).replace("$BATCH_TASK_INDEX",
                                                                                        str(batch_task_index))

    for key in task_environments[batch_task_index].variables:
        input_str = input_str.replace("${" + key + "}", task_environments[batch_task_index].variables[key])
        input_str = input_str.replace(key, task_environments[batch_task_index].variables[key])
    return input_str


def write_job_csv(output_path, created_job, command, task_environments):
    job_uid = created_job.uid
    if output_path:
        bucket_name, path = helper.split_uri_2_bucket_prefix(output_path)
        header = True
        csv_str = ""
        for index, t in enumerate(task_environments):
            if header:
                csv_str = "BATCH_TASK_INDEX," + ",".join(t.variables.keys()) + ",command\n"
                header = False
            csv_str += magic_replace(",".join([str(index)] + list(t.variables.values())), index, task_environments)
            csv_str += "," + helper.obscure_sensitive_info(magic_replace(command, index, task_environments)) + "\n"

        bucket = gcs.get_bucket(bucket_name)
        if path == "":
            f_name = f"{job_uid}.csv"
        else:
            f_name = f"{path}/{job_uid}.csv"
        blob = bucket.blob(f"{f_name}")
        Logger.info(f"Uploading status information into gs://{bucket.name}/{f_name}")
        blob.upload_from_string(
            data=csv_str,
            content_type='text/csv'
        )


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

    args_parser.add_argument('-d', dest="dir_path",
                             help="Path to input gcs directory where START_PIPELINE file to be uploaded")
    return args_parser


if __name__ == "__main__":
    # job_created = create_container_job(PROJECT_ID, REGION, JOB_NAME)
    # print(job_created)
    # name = job_created.name.split("/")[-1]
    # job_uid = job_created.uid
    # created_time = job_created.create_time
    # runnable = job_created.task_groups[0].task_spec.runnables[0]

    # jobs = list_jobs(PROJECT_ID, REGION)
    # print(jobs)
    parser = get_args()
    args = parser.parse_args()
    name = "START_PIPELINE"

    dir_path = args.dir_path
    if dir_path:
        name = f"{dir_path}/START_PIPELINE"

    bucket = f'{PROJECT_ID}-input'
    Logger.info(f"Using file_name={name}, bucket={bucket}")
    run_dragen_job({'bucket': bucket,
                    'name': name,
                    }, None)


