- [Introduction](#introduction)
- [Create GCP Environment for DRAGEN](#create-gcp-environment-for-dragen)
  * [Pre-requisites](#pre-requisites)
  * [GCP Infrastructure](#gcp-infrastructure)
- [Upload Required Input Data](#upload-required-data)
- [Trigger the pipeline](#trigger-the-pipeline)
  * [Directly from GCS](#directly-from-gcs)
  * [From shell](#from-shell)
- [Configuration](#configuration)
- [References](#references)


## Introduction

This is a solution using GCP Cloud Storage -> Pub/Sub -> Cloud Function -> Batch API to trigger execution of the Dragen Software on FPGA dedicated hardware.

It offers a simplified user experience:
* Easy provisioning of the infrustructure
* Easy way to trigger pipeline execution, by dropping an empty file called START_PIPELINE into the Cloud Storage bucket with required input data.
  * The Pipeline execution can be configured by changing config.json file inside the  gs://$PROJECT_ID-input directory


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
* Uploads `config.json`  with  Jarvice and Dragen options
* Deploys Cloud Function - to trigger batch Job on GCS event


## Upload Required Data

> Download data using your development machine (Cloud Shell will not have enough capacity). 

* Upload FASTQ ORA data to `gs://${PROJECT_ID}-input/[your_folder]/inputs` ([your_folder] is optional)
  * For pipeline to work, there should be two `.ora` files, one containing `R1` and another `R2` in the name.
  * As sample data, you could use `HG002.novaseq.pcr-free.35x.R1.fastq.ora`, `HG002.novaseq.pcr-free.35x.R2.fastq.ora` from [Google Drive DRAGEN_data](https://drive.google.com/corp/drive/folders/16qFUVK-QNGtiNnr4yO-JCZnBNHvrGC11) into `data` directory. Ask [Shyamal Mehtalia](mailto:smehtalia@illumina.com) for access. 


* Upload Reference hg38 data to `gs://${PROJECT_ID}-input/[your_folder]/references/`
  * For pipeline to work, the reference directory should start with `hg38`:
  * As sample data, Copy `hg38_alt_masked_cnv_graph_hla_rna-8-r2.0-1` (you will need to install [wget](https://www.gnu.org/software/wget/) locally in case it is not installed) into `data` directory:
    ```shell~~~~
    cd data
    wget https://webdata.illumina.com/downloads/software/dragen/hg38%2Balt_masked%2Bcnv%2Bgraph%2Bhla%2Brna-8-r2.0-1.run
    chmod +x hg38+alt_masked+cnv+graph+hla+rna-8-r2.0-1.run
    ./hg38+alt_masked+cnv+graph+hla+rna-8-r2.0-1.run  --target hg38+alt_masked+cnv+graph+hla+rna-8-r2.0-1
    cd ..
    ```
* Upload `lenadata` to `gs://${PROJECT_ID}-input/[your_folder]/references/`
  * As sample data, use [lenadata folder](https://drive.google.com/corp/drive/folders/1pOFmVh8YwsH1W9e8En7jxzEYF_0O2rmr). Unzip folder (`unzip lendata-xxxx.zip`) into `data` directory (should end up as `data/lendata/refbin` and `data/lendata/lena_index`)
  

## Trigger the pipeline

### Directly from GCS
Drop empty file named `START_PIPELINE` (`cloud_function/START_PIPELINE`) inside `gs://${PROJECT_ID}-input/[your_folder]`

### From shell
Following command will drop START_PIPELINE file into the `gs://${PROJECT_ID}-input/[your_folder]` directory:
```shell
./start_pipeline.sh your_folder
```

Alternatively, without [you_folder] it will drop to the input root:
```shell
./start_pipeline.sh
```

## Configuration
Sample configuration file is uploaded to the `gs://$PROJECT_ID-input` folder during the setup step.
This file can be modified in order to adjust the pipeline execution.

If the job is triggered inside a sub-directory, for example: `gs://$PROJECT_ID-input/john/test-run1`
(by uploading `START_PIPELINE` into the `gs://$PROJECT_ID-input/john/test-run1` directory), then system will first check if there is a local `config.json` file present.
If not, it will check a parent directory, until it reaches the top `gs://$PROJECT_ID-input`. This allows multiple users to be using same input bucket, while having different configuration per each individual job run.


## References
* Sample data downloaded from  [Google Drive DRAGEN_data](https://drive.google.com/corp/drive/folders/1nwewtQCu2KarG-zw_pv4XZhwS8XOc2lo).

* The following [README file](https://docs.google.com/document/d/1Uawxi4UrY_jjsD6Mp-n1o-_gMUB6eSMA5vIWdhVHS3U/edit#heading=h.z1g5ff2ylnea) was used as original input.
