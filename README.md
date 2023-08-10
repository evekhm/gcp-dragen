- [Introduction](#introduction)
- [Create GCP Environment for DRAGEN](#create-gcp-environment-for-dragen)
  * [Pre-requisites](#pre-requisites)
  * [GCP Infrastructure](#gcp-infrastructure)
- [Trigger the pipeline](#trigger-the-pipeline)
  * [Directly from GCS](#directly-from-gcs)
  * [From shell](#from-shell)
- [Configuration](#configuration)
- [References](#references)


## Introduction

This is a solution using GCP Cloud Storage -> Pub/Sub -> Cloud Function -> Batch API to trigger execution of the Dragen Software on FPGA dedicated hardware.

It offers a simplified user experience:
* Easy provisioning of the infrastructure,
* Easy way to trigger pipeline execution, by dropping an empty file called START_PIPELINE into the Cloud Storage bucket with required configuration data.


![](docs/ArchitectureOverview.png)

![](docs/Configuration.png)



## Pre-requisites

### License Information
Following licenses and keys are required to operate this solution:
* Illumina
> Obtain a DRAGEN license key from Illumina.
* Atos
> Obtain a JARVICE username and API key from  Atos/Nimbix.  
> If you do not have a JARVICE username and API key for the Atos FPGA Acceleration for Illumina DRAGEN Bio-IT Platform solution, please contact support@nimbix.net.


### Infrastructure Preparation

In case you do not have org level admin access to modify Policy Constraints, make sure the following policies are disabled for your GCP project or request your admin to do so.
If you have Org Level admin access, this could be done programmatically when setting up the system:

| Policy Name                          |  Constraint Name     |  Effective Polciy   |
|--------------------------------------|-----|-----|
| Disable service account creation     |  constraints/iam.disableServiceAccountCreation   |  Not Enforced    |
| Disable service account key creation |   constraints/iam.disableServiceAccountKeyCreation  |  Not Enforced    |
| Allow list for External IP address   |    constraints/compute.vmExternalIpAccess  |  Not Enforced    |
| Require ShieldedVm                                      |   constraints/compute.requireShieldedVm   | Not Enforced     |
| Restrict authentication types                                    |  constraints/storage.restrictAuthTypes   |  Not Enforced    |

For `Restrict authentication types` - either should AllowAll or following projects need to be added:

- `projects/illumina-dragen`
- `projects/atos-illumina-public`
- `projects/batch-custom-image`


Following Google APIs need to be enabled (in case you do not have admin level access and this need to be requested separately. Otherwise, step could be skipped):

- The follow APIs will be used:
  * orgpolicy.googleapis.com
  * compute.googleapis.com
  * pubsub.googleapis.com
  * batch.googleapis.com
  * cloudresourcemanager.googleapis.com
  * secretmanager.googleapis.com
  * logging.googleapis.com
  * storage.googleapis.com
  * cloudfunctions.googleapis.com
  * cloudbuild.googleapis.com
  * cloudresourcemanager.googleapis.com

## GCP Setup

* Create GCP Project with assigned project account
* Open Cloud Shell and set env variable accordingly:
  ```shell
  export PROJECT_ID=
  ```

* Point to the Cloud Storage Bucket containing Samples Data:
  ```shell
  export DATA_BUCKET_NAME=broad-gp-dragen-demo
  ```
* Use your Dragen license from Illumina (`ILLUMINA_LICENSE`), JARVICE username (`JXE_USERNAME`) and api key (`JXE_APIKEY`)to set env variables (to be used during the deployment)
  ```shell
  export ILLUMINA_LICENSE=
  export JXE_APIKEY=
  export JXE_USERNAME=
  ```
  
* At this point you either have manually followed the pre-requisites to disable policy constraints, or you have org level admin rights  and this could be done for you, when following variable is set: 

```shell
export DISABLE_POLICY=true
```

* Run following command to provision required infrastructure (Org policies, VPC, GCP Buckets, HMAC keys):
  ```shell
  ./setup.sh
  ```
> Command will take ~ 5 minutes and you should see following message at the end of the execution: ` "Success! Infrastructure deployed and ready!"` with next steps described.
 
This command executes following steps:
* Enables required APIs
* Sets required constraints
* Creates Network/Subnet and required Firewall rules
* Creates GCS Bucket for input and output
* Creates HMAC keys (stores as GCP secrets)
* Creates Secrets with License keys (stores as GCP secrets)
* Creates Service Account with required permissions to run the Batch Job
* Uploads sample config files  with batch, Jarvice and Dragen options
* Deploys Cloud Function - to trigger batch Job on GCS event

## Configuration
There are sample configuration files generated to inspect:

* $PROJECT_ID-input/cram_test/403/batch_config.json  - to Run cram jobs using 4.03 version
  * References `gs://$PROJECT_ID-config/cram_config_403.json` config
* $PROJECT_ID-input/cram_test/310/batch_config.json  - to Run cram jobs using 3.10 version
  * References `gs://$PROJECT_ID-config/cram_config_310.json` config
* $PROJECT_ID-input/cram_test/378/batch_config.json  - to Run cram jobs using 3.78~~~~ version
  * References `gs://$PROJECT_ID-config/cram_config_378.json` config
* $PROJECT_ID-input/fastq_test/batch_config.json     - to Run fastq job using 4.03 version
  * References `gs://$PROJECT_ID-config/fastq_config.json` config

Batch configuration file describing amount of jobs in parallel and maximum job count for a run is must be named `batch_config.json`.
 
Inspect/modify/create new  `batch_config.json` and configuration files for the input (See samples in config )

Note (based on the suer requirements):
* ORA files in the same directory - are combined in a single command.
* Each CRAM file - is a separate command.

## Trigger the pipeline

Drop empty file named  `START_PIPELINE` (see  `cloud_function/START_PIPELINE`)  into the folder containing `batch_config.json` file (Must be inside `gs://${PROJECT_ID}-input` bucket, since it is configured to listen to the Pub/Sub Cloud Storage event )

Sample scripts to trigger for execution (to be run from the Cloud Shell):

* ./run_cram_403.sh - to trigger 4.03 execution of cram jobs (using `$PROJECT_ID-input/cram_test/403/batch_config.json`)
* ./run_fastq_403.sh - to trigger fastq 4.03 execution (using `$PROJECT_ID-input/fastq_test/batch_config.json`)
* ./run_cram_378.sh - to trigger 3.78 execution for cram sample (using `$PROJECT_ID-input/cram_test/378/batch_config.json`)

### From shell
Following command will drop START_PIPELINE file into the `gs://${PROJECT_ID}-input/[your_folder_path]` directory:
```shell
./start_pipeline.sh your_folder_path
```

> Note: Do not specify bucket name, since it always must be `gs://${PROJECT_ID}-input`

## Troubleshooting

### Exhausting ssh login profile
#### Error
```shell
ERROR: (gcloud.compute.ssh) INVALID_ARGUMENT: Login profile size exceeds 32 KiB. Delete profile values to make additional space.
```
![](docs/error.png)
#### Resolution

Clean up service account ssh keys:

```shell
./utils/cleanup_keys.sh
```

The command above will activate service account and clean up its keys.


## Supported versions

Following dragen `VERSION`(s) are supported:
```shell
 "jarvice_options": {
        "entrypoint": "/bin/bash",
        "jxe_app": "VERSION",
        "image_uri": "us-docker.pkg.dev/jarvice/images/illumina-dragen:v1.2-rc"
    }
```

**3.10.4** version of DRAGEN:
* "illumina-dragen_3_10_4n"

**3.7.8** version:
* "illumina-dragen_3_7_8n"


**4.0.3** version of DRAGEN
* "illumina-dragen_4_0_3n"


## References
* Sample data downloaded from  [Google Drive DRAGEN_data](https://drive.google.com/corp/drive/folders/1nwewtQCu2KarG-zw_pv4XZhwS8XOc2lo).

* The following [README file](https://docs.google.com/document/d/1Uawxi4UrY_jjsD6Mp-n1o-_gMUB6eSMA5vIWdhVHS3U/edit#heading=h.z1g5ff2ylnea) was used as original input.

## Loading batch Job details

```shell
gcloud batch jobs describe --location us-central1 $JOB_NAME 
```

## Sharing Code with the Customer

Configure the repo access control so customer can view or download it:
* Go to [cloud-ce-shared-csr project](https://source.cloud.google.com/cloud-ce-shared-csr?project=cloud-ce-shared-cs) in Cloud Source Repos
* Select [this repository](https://source.cloud.google.com/cloud-ce-shared-csr/evekhm-broad-dragen)
* Select the settings icon  (top right)
* Select Permissions
* In the Members box, add one or more customer's email address (They need to have a google account)
* Set Role to: Source repository-->Source Repository Reader
* Click Add

Your Customer can now clone the repository in their own environment. Provide the following instructions to the customer:
* Install the [Google Cloud SDK](https://cloud.google.com/sdk)
* Authenticate the SDK with their Google credentials

```shell
gcloud init
```

* Clone the repository (replace USERNAME-project-name with your repo name)
```shell
gcloud source repos clone evekhm-broad-dragen --project=cloud-ce-shared-csr
cd evekhm-broad-dragen
git checkout main
```
