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
## Create GCP Environment for DRAGEN



### Pre-requisites

Following licenses and keys are required to operate this solution:
* Illumina
> Obtain a DRAGEN license key from Illumina.
* Atos
> Obtain a JARVICE username and API key from  Atos/Nimbix.  
> If you do not have a JARVICE username and API key for the Atos FPGA Acceleration for Illumina DRAGEN Bio-IT Platform solution, please contact support@nimbix.net.


- The following list of **Organizational Policy Constraints** will be enabled on the Google Cloud Organization your GCP Project is in:

| Policy Name                          |  Constraint Name     |  Effective Polciy   |
|--------------------------------------|-----|-----|
| Disable service account creation     |  constraints/iam.disableServiceAccountCreation   |  Not Enforced    |
| Disable service account key creation |   constraints/iam.disableServiceAccountKeyCreation  |  Not Enforced    |
| Allow list for External IP address   |    constraints/compute.vmExternalIpAccess  |  Not Enforced    |
|  Require ShieldedVm                                      |   constraints/compute.requireShieldedVm   | Not Enforced     |
|  Restrict authentication types                                    |  constraints/storage.restrictAuthTypes   |  Not Enforced    |


<br>

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

### GCP Infrastructure

* Create GCP Project
* Open Cloud Shell and set env variable accordingly:
  ```shell
  export PROJECT_ID=
  ```

* Use your Dragen license from Illumina (`ILLUMINA_LICENSE`), JARVICE username (`JXE_USERNAME`) and api key (`JXE_APIKEY`)to set env variables (to be used during the deployment)
  ```shell
  export ILLUMINA_LICENSE=
  export JXE_APIKEY=
  export JXE_USERNAME=
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

## Preparations
* Prepare `batch_config.json` and configuration files for the input (See samples in config )



## Trigger the pipeline

Drop empty START_PIPELINE file into the folder inside `gs://${PROJECT_ID}-input` bucket
That folder must contain `batch_config.json` file



### Directly from GCS
Drop empty file named `START_PIPELINE` (`cloud_function/START_PIPELINE`) inside the required input directory. 

### From shell
Following command will drop START_PIPELINE file into the `gs://${PROJECT_ID}-input/[your_folder_path]` directory:
```shell
./start_pipeline.sh your_folder_path
```

> Note: Do not specify bucket name, since it always must be `gs://${PROJECT_ID}-input`


## Configuration
* Sample run configuration file is uploaded as `gs://$PROJECT_ID-input/config.json`  during the setup step.
* Batch configuration file describing amount of jobs in parallel and maximum job count for a run is defined in `gs://$PROJECT_ID-input/batch_config.json` file during the setup step.
These file can be modified in order to adjust the pipeline execution.

ORA files in the same directory - are combined in a single command.
Each CRAM file - is a separate command. 

Sometimes for ora group files (which belong to the same directory) you want to change `config.json` settings per run. This could be done, by adding local `config.json` file into the same directory along with ora files.
For example, if ORA files are located in the  `gs://$PROJECT_ID-input/john/test-run1` location, system will first check if there is a local `config.json` file inside `test-run1` and if not, will check the parent directories until it reaches the top input bucket..
This allows multiple users to be using same input bucket, while having different configuration per each individual job run.
Notice, that no merging is done.

batch_config.json is a global setting for the run and is expected to be inside the directory in which START_PIPELINE is triggered.  
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



## References
* Sample data downloaded from  [Google Drive DRAGEN_data](https://drive.google.com/corp/drive/folders/1nwewtQCu2KarG-zw_pv4XZhwS8XOc2lo).

* The following [README file](https://docs.google.com/document/d/1Uawxi4UrY_jjsD6Mp-n1o-_gMUB6eSMA5vIWdhVHS3U/edit#heading=h.z1g5ff2ylnea) was used as original input.

## Loading batch Job details

```shell
gcloud batch jobs describe --location us-central1 $JOB_NAME 
```
