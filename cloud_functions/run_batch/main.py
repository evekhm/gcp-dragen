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
from typing import List, Dict

from google.api_core.exceptions import NotFound
from google.cloud import batch_v1
from google.cloud import storage

from commonek.bq_helper import stream_data_to_bigquery
from commonek.csv_helper import trigger_job_from_csv
from commonek.dragen_command_helper import DragenCommand
from commonek.gcs_helper import file_exists
from commonek.gcs_helper import get_rows_from_file
from commonek.helper import get_secret_value
from commonek.helper import split_uri_2_bucket_prefix
from commonek.logging import Logger
from commonek.params import BIGQUERY_DB_JOB_ARRAY
from commonek.params import CRAM_INPUT
from commonek.params import FASTQ_INPUT
from commonek.params import FASTQ_LIST_INPUT
from commonek.params import INPUT_PATH
from commonek.params import JOBS_LIST_URI
from commonek.params import JOB_LABEL_NAME
from commonek.params import JOB_LIST_FILE_NAME
from commonek.params import OUTPUT_PATH
from commonek.params import PROJECT_ID
from commonek.params import REGION
from commonek.params import SAMPLE_ID
from commonek.params import TRIGGER_FILE_NAME

BATCH_CONFIG_FILE_NAME = "batch_config.json"
# API clients
gcs = storage.Client()  # cloud storage
batch = None  # batch job client

JOB_NAME = os.getenv("JOB_NAME_SHORT", "job-dragen")
NETWORK = os.getenv("GCLOUD_NETWORK", "default")
SUBNET = os.getenv("GCLOUD_SUBNET", "default")

# Secrets
S3_ACCESS_KEY_SECRET_NAME = os.getenv("S3_ACCESS_KEY_SECRET_NAME", "batchS3AccessKey")
S3_SECRET_KEY_SECRET_NAME = os.getenv("S3_SECRET_KEY_SECRET_NAME", "batchS3SecretKey")
ILLUMINA_LIC_SERVER_SECRET_NAME = os.getenv(
    "ILLUMINA_LIC_SERVER_SECRET_NAME", "illuminaLicServer"
)
JARVICE_API_KEY_SECRET_NAME = os.getenv("JARVICE_API_KEY_SECRET_NAME", "jarviceApiKey")
JARVICE_API_USERNAME_SECRET_NAME = os.getenv(
    "JARVICE_API_USERNAME_SECRET_NAME", "jarviceApiUsername"
)


SERVICE_ACCOUNT_EMAIL = os.getenv(
    "JOB_SERVICE_ACCOUNT", f"illumina-script-sa@{PROJECT_ID}.iam.gserviceaccount.com"
)
IMAGE_URI_DEFAULT = os.getenv(
    "IMAGE_URI", "us-docker.pkg.dev/jarvice/images/jarvice-dragen-service:1.0-rc.5"
)
PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE = os.getenv(
    "PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE", "job-dragen-task-state-change-topic"
)
PUBSUB_TOPIC_BATCH_JOB_STATE_CHANGE = os.getenv(
    "PUBSUB_TOPIC_BATCH_JOB_STATE_CHANGE", "job-dragen-job-state-change-topic"
)


def load_config(bucket_name, file_path, recursive_find=False):
    Logger.info(f"load_config with bucket={bucket_name}, file_path={file_path}")
    file_name = os.path.basename(file_path)

    try:
        if bucket_name and gcs.get_bucket(bucket_name).exists():
            buc = gcs.get_bucket(bucket_name)
            blob = buc.blob(file_path)
            if blob.exists():
                Logger.info(
                    f"======== loading configuration from gs://{bucket_name}/{file_path}..."
                )
                data = json.loads(blob.download_as_text(encoding="utf-8"))
                return data
            elif recursive_find:
                Logger.warning(
                    f"Warning: file_path = {file_path} does not exist inside {bucket_name}. "
                )
                if file_path != os.path.basename(file_path):
                    dir_path = "/".join(os.path.dirname(file_path).split("/")[:-1])
                    Logger.info(
                        f"Checking if {file_name} exists in the top level folder {dir_path}."
                    )
                    if dir_path == "":
                        file_path = file_name
                    else:
                        file_path = f"{dir_path}/{file_name}"
                    return load_config(bucket_name, file_path)
                else:
                    Logger.error(
                        f"Error: file gs://{bucket_name}/{file_path} does not exist"
                    )
            else:
                Logger.error(
                    f"Error: file gs://{bucket_name}/{file_path} does not exist"
                )

        else:
            Logger.error(f"Error: bucket does not exist {bucket_name}")
    except Exception as e:
        Logger.error(
            f"Error: while obtaining file from GCS gs://{bucket_name}/{file_path} {e}"
        )
    return {}


def run_dragen_job(event, context):
    Logger.info(f"============================ run_dragen_job - Event received {event} with context {context}")
    bucket_name, file_path = None, None

    if "bucket" in event:
        bucket_name = event["bucket"]

    if "name" in event:
        file_path = event["name"]

    assert bucket_name, "Bucket unknown where to run pipeline"
    assert file_path, "Filename unknown"

    Logger.info(
        f"run_dragen_job - Using PROJECT_ID = {PROJECT_ID}, region = {REGION},"
        f" job_name = {JOB_NAME}, network = {NETWORK},"
        f" subnet = {SUBNET}, "
        f"service_account_email = {SERVICE_ACCOUNT_EMAIL}"
    )

    # file=inputs/START_PIPELINE
    # bucket
    Logger.info(
        f"run_dragen_job - Received GCS finalized event on bucket={bucket_name}, file_path={file_path} "
    )
    filename = os.path.basename(file_path)

    if filename != TRIGGER_FILE_NAME:
        Logger.info(
            f"run_dragen_job - Skipping action on {filename}, since waiting for {TRIGGER_FILE_NAME} to trigger pipe-line"
        )
        return

    Logger.info(f"run_dragen_job - handling {TRIGGER_FILE_NAME}...")
    bucket = gcs.get_bucket(bucket_name)

    dirs = os.path.dirname(file_path)
    prefix = ""
    if dirs is not None and dirs != "":
        prefix = dirs + "/"

    file_string = ""
    batch_config_file_name = BATCH_CONFIG_FILE_NAME
    job_labels = None

    try:
        blob = bucket.blob(file_path)
        file_string = blob.download_as_text()
    except NotFound as exc:
        Logger.warning(f"File not found {exc}")
        # Still we want to proceed, will be same behaviour as empty file uploaded

    if (
        file_string != ""
    ):  # START_PIPELINE can contain additional info, that could be parsed
        try:
            json_string = json.loads(file_string)
            job_labels = {JOB_LABEL_NAME: json_string[JOB_LABEL_NAME]}
            batch_config_file_name = json_string["config"]
            Logger.info(
                f"run_dragen_job - job_labels = {job_labels}, config_file_name={batch_config_file_name}"
            )
        except Exception as exc:
            Logger.warning(
                f"Caught exception when parsing json file {file_string} - {exc}"
            )
            pass

        batch_config_file_path = f"{prefix}{batch_config_file_name}"
        return create_batch_job(bucket_name, batch_config_file_path, job_labels)

    jobs_list_path = f"{prefix}{JOB_LIST_FILE_NAME}"
    # Check if jobs.csv file or if jobs list is located in the bucket
    if file_exists(bucket_name, jobs_list_path):
        Logger.info(f"run_dragen_job - Handling {jobs_list_path}... ")
        bucket = gcs.get_bucket(bucket_name)
        jobs_list_blob = bucket.blob(jobs_list_path)
        csv_string = jobs_list_blob.download_as_text()
        Logger.info(f"run_dragen_job - csv_string = {csv_string}")

        # Make sure that job_list file is uploaded to where scheduler is expected to read it from
        # (cannot have multiple scheduled jobs!)
        if f"gs://{bucket_name}/{jobs_list_path}" != JOBS_LIST_URI:
            Logger.info(
                f"run_dragen_job - Copying gs://{bucket_name}/{jobs_list_path} to "
                f"location={JOBS_LIST_URI} where scheduler expects it to be... "
            )
            bucket_name_jobs_list, jobs_list_uri_path = split_uri_2_bucket_prefix(
                JOBS_LIST_URI
            )
            bucket = gcs.get_bucket(bucket_name_jobs_list)
            jobs_list_blob_copy = bucket.blob(jobs_list_uri_path)
            jobs_list_blob_copy.upload_from_string(csv_string)

        # Trigger First job in the list
        trigger_job_from_csv(bucket_name, jobs_list_path)
        return

    batch_config_file_path = f"{prefix}{batch_config_file_name}"
    return create_batch_job(bucket_name, batch_config_file_path, job_labels)


def create_batch_job(bucket_name, batch_config_path, job_labels):
    Logger.info(f"create_batch_job - config_path={batch_config_path}")
    if not file_exists(bucket_name, batch_config_path):
        Logger.error(f"create_batch_job -  {batch_config_path} file not found")
        return

    batch_config = load_config(bucket_name=bucket_name, file_path=batch_config_path)
    if batch_config == {}:
        Logger.error("create_batch_job - Error: batch_options could not be retrieved.")
        return
    else:
        Logger.info(f"create_batch_job - batch_options={batch_config}")
    run_options = batch_config.get("run_options", {})
    input_option = batch_config.get("input_options", {})
    input_type = input_option.get("input_type")
    if input_type.lower() == CRAM_INPUT:
        extensions = [".cram"]
    elif input_type.lower() == FASTQ_INPUT:
        extensions = [".ora", ".gz"]
    else:
        Logger.error(f"create_batch_job - Error, unsupported type {input_type}")
        return
    config_file_name = input_option.get("config", None)
    if config_file_name:
        config_bucket, config_prefix = split_uri_2_bucket_prefix(config_file_name)
        config_options = load_config(config_bucket, config_prefix)
        if config_options == {}:
            print(
                f"create_batch_job - Error, could not load configuration options from {config_file_name}"
            )
            return
    else:
        print(
            f"create_batch_job - Error, config path is not properly specified for the input {input_option}"
        )
        return
    samples_list = []
    input_list_uri = input_option.get("input_list", None)
    if input_list_uri:
        samples_list.extend(get_rows_from_file(input_list_uri))
    input_path = input_option.get("input_path", None)
    if input_path:
        samples_list.extend(get_samples_list_from_path(input_path, extensions))
    if len(samples_list) == 0:
        Logger.error("create_batch_job - Error, no input files detected")
        return
    Logger.info(
        f"create_batch_job - samples_list - {len(samples_list)} loaded from input_list_uri={input_list_uri} and "
        f"input_path={input_path}"
    )
    dragen_options, jarvice_options = get_options(config_options)
    command, env_variables = task_info(
        dragen_options=dragen_options,
        jarvice_options=jarvice_options,
        samples_list=samples_list,
        input_type=input_type,
    )
    task_count = None
    for key in env_variables:
        if task_count is not None:
            assert task_count == len(env_variables[key]), (
                f"Env variables not filled in consistently for all tasks"
                f" {env_variables}"
            )
        else:
            task_count = len(env_variables[key])
    return create_script_job(
        run_options=run_options,
        jarvice_options=jarvice_options,
        job_labels=job_labels,
        input_type=input_type,
        command=command,
        variables=env_variables,
    )


def task_info(dragen_options, jarvice_options, samples_list, input_type):
    date_str = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%d-%H-%M-%S"
    )
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
            env_variables[OUTPUT_PATH] = [
                dragen_options.get("--output-directory").replace("<date>", date_str)
            ]
        inputs = " ${INPUT_PATH}"
        command = get_task_command(
            dragen_options=dragen_options,
            jarvice_options=jarvice_options,
            inputs=inputs,
            replace_options=replace_options,
        )

        return command, env_variables
        # commands.append((image_uri, entrypoint, command, f",{f_uris}", output_path))
    elif input_type == CRAM_INPUT:
        env_variables = {SAMPLE_ID: [], INPUT_PATH: [], OUTPUT_PATH: []}
        for sample in samples_list:
            if len(sample) >= 2:
                sample_id = sample[0]
                env_variables[SAMPLE_ID].append(sample_id)
                env_variables[INPUT_PATH].append(sample[1].replace("gs://", "s3://"))
                if "--output-directory" in dragen_options:
                    env_variables[OUTPUT_PATH].append(
                        dragen_options.get("--output-directory")
                        .replace("${SAMPLE_ID}", sample_id)
                        .replace("<date>", date_str)
                    )
            else:
                Logger.warning(
                    f"Loaded samples were not in the expected format {sample}"
                )
        inputs = " --cram-input ${INPUT_PATH}"
        command = get_task_command(
            dragen_options=dragen_options,
            jarvice_options=jarvice_options,
            inputs=inputs,
            replace_options=replace_options,
        )

        return command, env_variables

    elif input_type == FASTQ_LIST_INPUT:
        inputs = " --fastq-list"  # TODO
        Logger.error("Method Not implemented yet")
    else:
        Logger.error(f"Error, unsupported input_type {input_type}")

    return None, None


def get_samples_list_from_path(path_uri: str, extensions: List[str]):
    Logger.info(f"get_samples_list_from_path - {path_uri}")
    bucket_name, prefix = split_uri_2_bucket_prefix(path_uri)
    if prefix != "":
        prefix = prefix + "/"

    input_list = []  # (sample_name, uri)

    # for b in gcs.list_blobs(bucket_name, prefix=f"{dir_name}", delimiter="/"):
    for b in gcs.list_blobs(bucket_name, prefix=f"{prefix}"):
        for extension in extensions:
            if b.name.lower().endswith(extension.lower()):
                sample_name = os.path.splitext(os.path.basename(b.name))[0]
                input_list.append([sample_name, f"s3://{bucket_name}/{b.name}"])

    Logger.info(f"get_samples_list_from_path - input_list={input_list}")
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
    Logger.info(
        f"Using PROJECT_ID = {PROJECT_ID}, region = {REGION},"
        f" job_name = {JOB_NAME}, network = {NETWORK},"
        f" subnet = {SUBNET}, "
        f"service_account_email = {SERVICE_ACCOUNT_EMAIL}"
    )

    dragen_app = jarvice_options.get("dragen_app", "illumina-dragen_3_7_8n")
    api_host = jarvice_options.get("api_host", "https://illumina.nimbix.net/api")
    jarvice_machine_type = jarvice_options.get("jarvice_machine_type", "nx1")
    stub_script = jarvice_options.get("stub", None)

    # Check secrets are valid
    access_key = get_secret_value(S3_ACCESS_KEY_SECRET_NAME, PROJECT_ID)
    access_secret = get_secret_value(S3_SECRET_KEY_SECRET_NAME, PROJECT_ID)
    illumina_license = get_secret_value(ILLUMINA_LIC_SERVER_SECRET_NAME, PROJECT_ID)
    jxe_apikey = get_secret_value(JARVICE_API_KEY_SECRET_NAME, PROJECT_ID)
    jxe_username = get_secret_value(JARVICE_API_USERNAME_SECRET_NAME, PROJECT_ID)
    assert access_key, "Could not retrieve access_key for input bucket"
    assert access_secret, "Could not retrieve access_secret for input bucket"
    assert illumina_license, "Could not retrieve illumina_license"
    assert jxe_username, "Could not retrieve jxe_username "
    assert jxe_apikey, "Could not retrieve jxe_apikey"

    dragen_options_replaced = get_dragen_command(dragen_options, replace_options)
    dragen_options_str = ""
    for key in dragen_options_replaced:
        dragen_options_str += f""" {key} {dragen_options_replaced[key]}"""

    command = (
        f"--api-host "
        f"{api_host} "
        f"--machine "
        f"{jarvice_machine_type} "
        f"--dragen-app "
        f"{dragen_app} "
        f"--google-sa "
        f"{SERVICE_ACCOUNT_EMAIL} "
        f"-- "
        f""" {inputs}"""
        f""" {dragen_options_str} """
    )
    dragen_command = DragenCommand(command, stub_script)
    Logger.info(f"DRAGEN Command: {dragen_command}")
    return dragen_command


def get_options(config):
    dragen_options = config.get("dragen_options", {})
    assert dragen_options != {}, "Error: dragen_options could not be retrieved"

    jarvice_options = config.get("jarvice_options", {})
    assert jarvice_options != {}, "Error: jarvice_options could not be retrieved"

    return dragen_options, jarvice_options


def create_script_job(
    run_options,
    command: DragenCommand,
    jarvice_options,
    job_labels,
    variables,
    input_type,
):
    """
    This method shows how to create a sample Batch Job that will run
    a simple command on Cloud Compute instances.

    Returns:
        A job object representing the job created.
    """

    image_uri = jarvice_options.get("image_uri", IMAGE_URI_DEFAULT)
    entrypoint = jarvice_options.get("entrypoint", "/bin/bash")

    # We can specify what resources are requested by each task.
    resources = batch_v1.ComputeResource()

    # in milliseconds per cpu-second. This means the task requires 2 whole CPUs.
    resources.cpu_milli = run_options.get("cpu_milli", 1000)
    resources.memory_mib = run_options.get("memory_mib", 512)
    machine = run_options.get("machine", "e2-micro")
    parallelism = run_options.get("parallelism", 3)

    # Tasks are grouped inside a job using TaskGroups.
    # Currently, it's possible to have only one task group.
    group = batch_v1.TaskGroup()
    task_count = len(variables[list(variables.keys())[0]])
    Logger.info(
        f"======== Creating job with {task_count} tasks and {parallelism} to be run in parallel ========"
    )

    task_environments = []
    if len(variables) > 0:
        for index in range(task_count):
            env_dict = {}
            for key in variables:
                env_dict[key] = variables[key][index]
            task_environments.append(batch_v1.Environment(variables=env_dict))

    group.parallelism = parallelism
    group.task_environments = task_environments
    group.task_count_per_node = 1

    # Policies are used to define on what kind of virtual machines the tasks will run on.
    # In this case, we tell the system to use "e2-standard-4" machine type.
    # Read more about machine types here: https://cloud.google.com/compute/docs/machine-types
    policy = batch_v1.AllocationPolicy.InstancePolicy()

    policy.machine_type = machine
    instances = batch_v1.AllocationPolicy.InstancePolicyOrTemplate()
    instances.policy = policy

    location_policy = batch_v1.AllocationPolicy.LocationPolicy()
    location_policy.allowed_locations = [f"regions/{REGION}"]

    # Set Network
    network_interface = batch_v1.AllocationPolicy.NetworkInterface()
    network_id = f"projects/{PROJECT_ID}/global/networks/{NETWORK}"
    subnetwork_id = f"projects/{PROJECT_ID}/regions/{REGION}/subnetworks/{SUBNET}"
    Logger.info(f"Using network_id={network_id}")
    Logger.info(f"Using subnetwork_id={subnetwork_id}")
    network_interface.network = network_id
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

    task_notification = batch_v1.JobNotification()
    task_notification.pubsub_topic = (
        f"projects/{PROJECT_ID}/topics/{PUBSUB_TOPIC_BATCH_TASK_STATE_CHANGE}"
    )
    message = batch_v1.JobNotification.Message()
    message.type_ = task_notification.Type.TASK_STATE_CHANGED
    task_notification.message = message

    job_notification = batch_v1.JobNotification()
    job_notification.pubsub_topic = (
        f"projects/{PROJECT_ID}/topics/{PUBSUB_TOPIC_BATCH_JOB_STATE_CHANGE}"
    )
    message = batch_v1.JobNotification.Message()
    message.type_ = job_notification.Type.JOB_STATE_CHANGED
    job_notification.message = message

    job_name = f"{JOB_NAME}-{uuid.uuid4().hex[:10]}"
    # Define what will be done as part of the job.
    runnable = batch_v1.Runnable()
    runnable.container = batch_v1.Runnable.Container()

    runnable.container.image_uri = image_uri
    runnable.container.entrypoint = entrypoint
    runnable.container.commands = command.get_commands()

    environment = batch_v1.Environment()
    environment.secret_variables = {
        "ILLUMINA_LIC_SERVER": f"projects/{PROJECT_ID}/secrets/{ILLUMINA_LIC_SERVER_SECRET_NAME}/versions/latest",
        "JARVICE_API_KEY": f"projects/{PROJECT_ID}/secrets/{JARVICE_API_KEY_SECRET_NAME}/versions/latest",
        "JARVICE_API_USER": f"projects/{PROJECT_ID}/secrets/{JARVICE_API_USERNAME_SECRET_NAME}/versions/latest",
        "S3_ACCESS_KEY": f"projects/{PROJECT_ID}/secrets/{S3_ACCESS_KEY_SECRET_NAME}/versions/latest",
        "S3_SECRET_KEY": f"projects/{PROJECT_ID}/secrets/{S3_SECRET_KEY_SECRET_NAME}/versions/latest",
    }
    # runnable.environment = environment

    # Define what will be done as part of the job.
    task = batch_v1.TaskSpec()
    task.compute_resource = resources

    task.max_retry_count = run_options.get("max_retry_count", 2)
    task.max_run_duration = run_options.get("max_run_duration", "7200s")
    task.runnables = [runnable]
    task.environment = environment
    group.task_spec = task

    job = batch_v1.Job()
    job.task_groups = [group]
    job.allocation_policy = allocation_policy
    job.notifications = [task_notification, job_notification]
    # We use Cloud Logging as it's an out of the box available option
    job.logs_policy = batch_v1.LogsPolicy()
    job.logs_policy.destination = batch_v1.LogsPolicy.Destination.CLOUD_LOGGING

    if job_labels:
        job.labels = job_labels
    create_request = batch_v1.CreateJobRequest()
    create_request.job = job

    create_request.job_id = job_name
    # The job's parent is the region in which the job will run
    create_request.parent = f"projects/{PROJECT_ID}/locations/{REGION}"

    global batch
    if not batch:
        batch = batch_v1.BatchServiceClient()

    created_job = batch.create_job(create_request)

    for i in range(task_count):

        # This is done to simplify BigQuery operations
        sample_id = None
        input_path = None
        output_path = None
        task_variables = {}
        if SAMPLE_ID in variables:
            sample_id = variables[SAMPLE_ID][i]

        if INPUT_PATH in variables:
            input_path = variables[INPUT_PATH][i]

        if OUTPUT_PATH in variables:
            output_path = variables[OUTPUT_PATH][i]

        for key in variables:
            task_variables[key] = variables[key][i]

        job_name = created_job.name.split("/")[-1]

        stream_job_array_to_bq(
            index=i,
            task_variables=task_variables,
            job_id=created_job.uid,
            job_name=job_name,
            job_label=created_job.labels[JOB_LABEL_NAME],
            command=command,
            task_environments=task_environments,
            output_path=output_path,
            input_type=input_type,
            input_path=input_path,
            sample_id=sample_id
        )


def stream_job_array_to_bq(index: int, task_variables: Dict[str], job_id: str,
                           job_name: str, job_label: str,
                           command: DragenCommand,
                           task_environments,
                           input_path,
                           input_type,
                           output_path,
                           sample_id,
                           ):
    now = datetime.datetime.now(datetime.timezone.utc)
    data = [
        {
            "batch_task_index": index,
            "variables": json.dumps(task_variables),
            "job_id": job_id,
            "timestamp": now.strftime("%Y-%m-%d %H:%M:%S"),
            "job_label": job_label,
            "command": magic_replace(command, index, task_environments),
            "job_name": job_name,
            "input_type": input_type,
            "input_path": input_path,
            "output_path": output_path,
            "sample_id": sample_id,
        }
    ]
    table_id = f"{PROJECT_ID}.{BIGQUERY_DB_JOB_ARRAY}"
    errors = stream_data_to_bigquery(data, table_id)
    if not errors:
        Logger.info(f"New rows have been added into {table_id} for job_id {job_id} ")
    elif isinstance(errors, list):
        error = errors[0].get("errors")
        Logger.error(
            f"Encountered errors while inserting rows into {table_id} for job_id {job_id}: {error}"
        )


def magic_replace(input_str, batch_task_index, task_environments):
    input_str = str(input_str)
    input_str = input_str.replace("${BATCH_TASK_INDEX}", str(batch_task_index)).replace(
        "$BATCH_TASK_INDEX", str(batch_task_index)
    )

    for key in task_environments[batch_task_index].variables:
        input_str = input_str.replace(
            "${" + key + "}", task_environments[batch_task_index].variables[key]
        )
        input_str = input_str.replace(
            key, task_environments[batch_task_index].variables[key]
        )
    return input_str


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
      """,
    )

    args_parser.add_argument(
        "-d",
        dest="dir_path",
        help="Path to input gcs directory where START_PIPELINE file to be uploaded",
    )
    return args_parser


if __name__ == "__main__":
    parser = get_args()
    args = parser.parse_args()
    name = "START_PIPELINE"

    args_dir_path = args.dir_path

    if args_dir_path:
        name = f"{args_dir_path}/START_PIPELINE"

    args_bucket_name = f"{PROJECT_ID}-trigger"
    Logger.info(f"Using file_name={name}, bucket={args_bucket_name}")
    run_dragen_job(
        {
            "bucket": args_bucket_name,
            "name": name,
        },
        None,
    )
