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
import sys
import uuid
from google.cloud import batch_v1
from google.cloud import secretmanager
from google.cloud import storage
from datetime import datetime

# API clients
gcs = storage.Client()  # cloud storage
sm = None  # secret_manager
batch = None  # batch job client


def load_config(bucketname, file_path):
  print(f"load_config with bucket={bucketname}, file_path={file_path}")
  file_name = os.path.basename(file_path)

  try:
    if bucketname and gcs.get_bucket(bucketname).exists():
      buc = gcs.get_bucket(bucketname)
      blob = buc.blob(file_path)
      if blob.exists():
        print(f"loading {file_path}...")
        data = json.loads(blob.download_as_text(encoding="utf-8"))
        return data
      else:
        print(f"Warning: file_path = {file_path} does not exist inside {bucketname}. ")
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

  project_id = os.environ.get("GCP_PROJECT",
                              os.environ.get("PROJECT_ID", ""))

  region = os.getenv('GCLOUD_REGION', "us-central1")
  job_name = os.getenv('JOB_NAME_SHORT', "dragen-job")
  network = os.getenv('GCLOUD_NETWORK', "default")
  subnet = os.getenv('GCLOUD_SUBNET', "default")

  trigger_file_name = os.getenv('TRIGGER_FILE_NAME', "START_PIPELINE")
  service_account_email = os.getenv('JOB_SERVICE_ACCOUNT')
  machine = os.getenv('GCLOUD_MACHINE', "n1-standard-2")
  print(f"Using PROJECT_ID = {project_id}, region = {region},"
        f" job_name = {job_name}, network = {network},"
        f" subnet = {subnet}, "
        f"service_account_email = {service_account_email},"
        f" machine = {machine}")

  # file=inputs/START_PIPELINE
  # bucket
  print(
      f"Received GCS finalized event on bucket={bucket}, file_path={file_path} ")
  filename = os.path.basename(file_path)

  if filename != trigger_file_name:
    print(
        f"Skipping action on {filename}, since waiting for {trigger_file_name} to trigger pipe-line")
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

  config = load_config(bucketname=bucket, file_path=f"{prefix}config.json")

  dragen_options = config.get("dragen_options", {})
  if dragen_options == {}:
    print(f"Error: dragen_options could not be retrieved, will be using hard-coded default values.")
  else:
    print(f"dragen_options={dragen_options}")
  jarvice_options = config.get("jarvice_options", {})
  if jarvice_options == {}:
    print(f"Error: jarvice_options could not be retrieved, will be using hard-coded default values.")
  else:
    print(f"jarvice_options={jarvice_options}")

  image_uri = jarvice_options.get('image_uri',
                                  'us-docker.pkg.dev/jarvice/images/illumina-dragen:dev')
  entrypoint = jarvice_options.get('entrypoint', '/bin/bash')
  command = get_command(bucket=bucket, prefix=prefix,
                        project_id=project_id, dragen_options=dragen_options,
                        jarvice_options=jarvice_options)

  print(command)
  return create_script_job(project_id=project_id, region=region,
                           job_name=job_name, network=network, subnet=subnet,
                           bucket=bucket,
                           service_account_email=service_account_email,
                           machine=machine, command=command,
                           image_uri=image_uri, entrypoint=entrypoint)


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


def get_ora_files(bucket_name, dir_name):
  print(f"bucket_name={bucket_name}, dir_name={dir_name}")
  ora_files = []
  for b in gcs.list_blobs(bucket_name, prefix=f"{dir_name}"):
    if b.name.lower().endswith(".ora"):
      ora_files.append(b.name)

  assert len(ora_files) != 0, f"No ora files detected inside {bucket_name}/{dir_name}"
  result = ""
  for index, ora_file in enumerate(ora_files):
    result = result + f" -{index + 1} s3://{bucket_name}/{ora_file} "
  return result


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


#path can be 'empty' or "/something
def get_command(bucket, prefix, project_id, dragen_options, jarvice_options):
  print(f"prefix={prefix}")
  region = os.getenv('GCLOUD_REGION', "us-central1")
  job_name = os.getenv('JOB_NAME_SHORT', "dragen-job")
  network = os.getenv('GCLOUD_NETWORK', "default")
  subnet = os.getenv('GCLOUD_SUBNET', "default")

  licence_secret = os.getenv('LICENSE_SECRET')
  s3_secret_name = os.getenv('S3_SECRET')
  service_account_email = os.getenv('JOB_SERVICE_ACCOUNT')
  machine = os.getenv('GCLOUD_MACHINE', "n1-standard-2")
  print(f"Using PROJECT_ID = {project_id}, region = {region},"
        f" job_name = {job_name}, network = {network},"
        f" subnet = {subnet}, "
        f" s3_secret_name = {s3_secret_name}, "
        f"service_account_email = {service_account_email},"
        f" machine = {machine}")

  assert licence_secret, "LICENSE_SECRET unknown"

  jxe_app = jarvice_options.get('jxe_app',
                                'illumina-dragen_4_0_3_13_g52a8599a')

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

  ora_inputs = get_ora_files(bucket_name=bucket, dir_name=prefix)

  date_str = datetime.now().strftime('%Y-%m-%d-%H-%M-%S')
  output_default = f"s3://{bucket}/output"

  lenadata_path = dragen_options.get('ora-reference', f"s3://{bucket}/references/lenadataXX")
  reference_path = dragen_options.get('reference', f"s3://{bucket}/references/hg38_alt_masked_cnv_graph_hla_rna-8-r2.0-1XX")

  print(f"ora_inputs={ora_inputs}, reference_path={reference_path}, lenadata_path={lenadata_path}")
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
            f"-f {ora_inputs}" \
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
            f"--output-file-prefix  {dragen_options.get('output-file-prefix', 'HG002_pure')} " \
            f"--output-directory  {dragen_options.get('output-directory', output_default)}/{prefix}{date_str} "  \
            f"--intermediate-results-dir {dragen_options.get('intermediate-results-dir', '/tmp/whole_genome/temp')} " \
            f"--logging-to-output-dir {dragen_options.get('logging-to-output-dir', 'true')} " \
            f"--syslogging-to-output-dir {dragen_options.get('syslogging-to-output-dir', 'true')} " \
            f"--lic-server https://{illumina_license}@license.edicogenome.com"
  print(command)
  return command


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


def create_script_job(project_id: str, region: str, network: str,
    subnet: str, job_name: str, bucket: str, service_account_email: str,
    machine: str, image_uri: str, command: str, entrypoint: str) -> batch_v1.Job:
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

  print(
      f"Submitting {job_name} to run script on input data inside gs://{bucket}")

  global batch
  if not batch:
    batch = batch_v1.BatchServiceClient()

  return batch.create_job(create_request)
  # [END batch_create_script_job]


if __name__ == "__main__":
  name = "START_PIPELINE"
  if len(sys.argv) > 1:
    name = f"{sys.argv[1]}/START_PIPELINE"

  project_id = os.environ.get("GCP_PROJECT",
                              os.environ.get("PROJECT_ID", ""))
  bucket = f'{project_id}-input'
  print(f"Using file_name={name}, bucket={bucket}")
  run_dragen_job({'bucket': bucket,
           'name': name, }, None)
