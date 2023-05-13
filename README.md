## Create GCP Environment for DRAGEN

### GCP Infrastructure

* Create GCP Project
* Open Cloud Shell and set env variable accordingly:
  ```shell
  export PROJECT_ID=
  ```

* Run following command to provision required infrastructure (Org policies, VPC, GCP Buckets, HMAC keys):
  ```shell
  ./setup.sh
  ```

### Download Sample Data

> Download data using your development machine (Cloud Shell will not have enough capacity). 

* Copy FASTQ data:
  * Download `HG002.novaseq.pcr-free.35x.R1.fastq.ora`, `HG002.novaseq.pcr-free.35x.R2.fastq.ora` from [Google Drive DRAGEN_data](https://drive.google.com/corp/drive/folders/16qFUVK-QNGtiNnr4yO-JCZnBNHvrGC11) into `data` directory.
    * 
* Copy `hg38_alt_masked_cnv_graph_hla_rna-8-r2.0-1` (you will need to install [wget](https://www.gnu.org/software/wget/) locally in case it is not installed) into `data` directory:
  ```shell
  cd data
  wget https://webdata.illumina.com/downloads/software/dragen/hg38%2Balt_masked%2Bcnv%2Bgraph%2Bhla%2Brna-8-r2.0-1.run
  chmod +x hg38+alt_masked+cnv+graph+hla+rna-8-r2.0-1.run
  ./hg38+alt_masked+cnv+graph+hla+rna-8-r2.0-1.run  --target hg38+alt_masked+cnv+graph+hla+rna-8-r2.0-1
  cd ..
  ```
* Copy `lendata`
  * Download [lendata folder](https://drive.google.com/corp/drive/folders/1pOFmVh8YwsH1W9e8En7jxzEYF_0O2rmr)
  * Unzip folder (`unzip lendata-xxxx.zip`) into `data` directory (should end up as `data/lendata/refbin` and `data/lendata/lena_index`)


### Upload Sample Data      
```shell
./copy_to_gcs.sh
```

### Execute batch Job

```shell
./doit.sh
```

## References
* Sample data downloaded from  [Google Drive DRAGEN_data](https://drive.google.com/corp/drive/folders/1nwewtQCu2KarG-zw_pv4XZhwS8XOc2lo).

* The following [README file](https://docs.google.com/document/d/1Uawxi4UrY_jjsD6Mp-n1o-_gMUB6eSMA5vIWdhVHS3U/edit#heading=h.z1g5ff2ylnea) was used as original input. 

