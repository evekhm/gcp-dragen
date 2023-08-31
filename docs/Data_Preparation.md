## Upload Required Data

> Download data using your development machine (Cloud Shell will not have enough capacity).

* Upload FASTQ ORA data to `gs://${PROJECT_ID}-input/inputs`
    * As sample data, you could use `HG002.novaseq.pcr-free.35x.R1.fastq.ora`, `HG002.novaseq.pcr-free.35x.R2.fastq.ora` from [Google Drive DRAGEN_data](https://drive.google.com/corp/drive/folders/16qFUVK-QNGtiNnr4yO-JCZnBNHvrGC11) into `data` directory. Ask [Shyamal Mehtalia](mailto:smehtalia@illumina.com) for access.


* Upload Reference hg38 data to `gs://${PROJECT_ID}-input/references/`
    * As sample data, Copy `hg38_alt_masked_cnv_graph_hla_rna-8-r2.0-1` (you will need to install [wget](https://www.gnu.org/software/wget/) locally in case it is not installed) into `data` directory:
      ```shell~~~~
      cd data
      wget https://webdata.illumina.com/downloads/software/dragen/hg38%2Balt_masked%2Bcnv%2Bgraph%2Bhla%2Brna-8-r2.0-1.run
      chmod +x hg38+alt_masked+cnv+graph+hla+rna-8-r2.0-1.run
      ./hg38+alt_masked+cnv+graph+hla+rna-8-r2.0-1.run  --target hg38+alt_masked+cnv+graph+hla+rna-8-r2.0-1
      cd ..
      ```
* Upload `lenadata` to `gs://${PROJECT_ID}-input/references/`
    * As sample data, use [lenadata folder](https://drive.google.com/corp/drive/folders/1pOFmVh8YwsH1W9e8En7jxzEYF_0O2rmr). Unzip folder (`unzip lendata-xxxx.zip`) into `data` directory (should end up as `data/lendata/refbin` and `data/lendata/lena_index`)

    