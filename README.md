## Create GCP Environment for DRAGEN

### Pre-requisites

Following licenses and keys are required to operate this solution:
* Illumina 
> Obtain a DRAGEN license key from Illumina.  
* Atos
> Obtain a JARVICE username and API key from  Atos/Nimbix.  
> If you do not have a JARVICE username and API key for the Atos FPGA Acceleration for Illumina DRAGEN Bio-IT Platform solution, please contact support@nimbix.net.

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
> Command will take ~ 4.5 minutes and you should see following message at the end of the execution: ` "Success! Infrastructure deployed and ready!"` with next steps described.
 

### Upload Required Input Data

> Download data using your development machine (Cloud Shell will not have enough capacity). 

* Upload FASTQ ORA data to `gs://${PROJECT_ID}-sample-data/[your_folder]/inputs` ([your_folder] is optional)
  * For pipeline to work, there should be two `.ora` files, one containing `R1` and another `R2` in the name.
  * As sample data, you could use `HG002.novaseq.pcr-free.35x.R1.fastq.ora`, `HG002.novaseq.pcr-free.35x.R2.fastq.ora` from [Google Drive DRAGEN_data](https://drive.google.com/corp/drive/folders/16qFUVK-QNGtiNnr4yO-JCZnBNHvrGC11) into `data` directory. Ask [Shyamal Mehtalia](mailto:smehtalia@illumina.com) for access. 


* Upload Reference hg38 data to `gs://${PROJECT_ID}-sample-data/[your_folder]/references/`
  * For pipeline to work, the reference directory should start with `hg38`:
  * As sample data, Copy `hg38_alt_masked_cnv_graph_hla_rna-8-r2.0-1` (you will need to install [wget](https://www.gnu.org/software/wget/) locally in case it is not installed) into `data` directory:
    ```shell
    cd data
    wget https://webdata.illumina.com/downloads/software/dragen/hg38%2Balt_masked%2Bcnv%2Bgraph%2Bhla%2Brna-8-r2.0-1.run
    chmod +x hg38+alt_masked+cnv+graph+hla+rna-8-r2.0-1.run
    ./hg38+alt_masked+cnv+graph+hla+rna-8-r2.0-1.run  --target hg38+alt_masked+cnv+graph+hla+rna-8-r2.0-1
    cd ..
    ```
* Upload `lenadata` to `gs://${PROJECT_ID}-sample-data/[your_folder]/references/`
  * As sample data, use [lenadata folder](https://drive.google.com/corp/drive/folders/1pOFmVh8YwsH1W9e8En7jxzEYF_0O2rmr). Unzip folder (`unzip lendata-xxxx.zip`) into `data` directory (should end up as `data/lendata/refbin` and `data/lendata/lena_index`)
  

### Trigger the pipeline

### Directly from GCS
Drop empty file named `START_PIPELINE` inside `gs://${PROJECT_ID}-sample-data/[your_folder]`

### From shell 
Following command will drop START_PIPELINE file into the `gs://${PROJECT_ID}-sample-data/[your_folder]` directory:
```shell
./start_pipeline.sh your_folder
```

### What is not built yet ()
## References
* Sample data downloaded from  [Google Drive DRAGEN_data](https://drive.google.com/corp/drive/folders/1nwewtQCu2KarG-zw_pv4XZhwS8XOc2lo).

* The following [README file](https://docs.google.com/document/d/1Uawxi4UrY_jjsD6Mp-n1o-_gMUB6eSMA5vIWdhVHS3U/edit#heading=h.z1g5ff2ylnea) was used as original input. 

