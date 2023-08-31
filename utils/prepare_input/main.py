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
import argparse
import json
import sys, os
from typing import List

sys.path.append(os.path.join(os.path.dirname(__file__), '../../common/src'))
from commonek.helper import split_uri_2_bucket_prefix
from commonek.gcs_helper import get_rows_from_file, write_gcs_blob
from commonek.logging import Logger


def doit(batch_size: int,
         parallelism: int,
         config_path: List[str],
         out_path: str,
         samples_input: List[str],
         input_type: str = "cram"):

    Logger.info(f"Preparing configurations using: \n"
                f"  - parallelism={parallelism} \n"
                f"  - batch_size={batch_size} \n"
                f"  - config_path_uri={config_path} \n"
                f"  - out_path={out_path} \n"
                f"  - samples_input_uri={samples_input} \n"
                f"  - input_type={input_type}")

    bucket_name, prefix = split_uri_2_bucket_prefix(out_path)
    if prefix != "":
        prefix += "/"

    jobs_csv_str = ""
    batch_config_dir = f"{prefix}jobs"
    input_list_dir = f"{prefix}input_list"
    job_count = 0
    for index, samples_input_uri in enumerate(samples_input):
        config_path_uri = config_path[index]
        job_count, jobs_csv_str = prepare_configuration(batch_size, config_path_uri, input_type, parallelism, samples_input_uri,
                              bucket_name, jobs_csv_str, batch_config_dir, input_list_dir, job_count)

    jobs_list_file = f"{prefix}jobs.csv"
    write_gcs_blob(bucket_name, jobs_list_file, jobs_csv_str)
    Logger.info("Done! Generated: ")
    Logger.info(f" - Batch configurations inside gs://{bucket_name}/{batch_config_dir}")
    Logger.info(f" - Chunked samples lists inside gs://{bucket_name}/{input_list_dir}")
    Logger.info(f" - Jobs list file gs://{bucket_name}/{jobs_list_file}")


def prepare_configuration(batch_size, config_path_uri, input_type, parallelism, samples_input_uri,
                          bucket_name, jobs_csv_str, batch_config_dir, input_list_dir, job_count):

    input_list = get_rows_from_file(samples_input_uri)
    input_name = os.path.splitext(os.path.basename(samples_input_uri))[0]
    for i in range(0, len(input_list), batch_size):
        x = i
        chunk_list = input_list[x:x + batch_size]
        batch_config_file = f"{batch_config_dir}/batch_config{job_count}.json"
        input_path_file = f"{input_list_dir}/{input_name}_{job_count}_{x}.txt"

        jobs_csv_str += f"job{job_count}, gs://{bucket_name}/{batch_config_file}\n"

        samples = ""
        for row in chunk_list:
            samples += " ".join(row) + "\n"

        write_gcs_blob(bucket_name, input_path_file, "collaborator_sample_id	cram_file_ref\n" + samples)
        write_batch_options(bucket_name, batch_config_file, parallelism, input_type, input_path_file, config_path_uri)
        job_count += 1

    return job_count, jobs_csv_str


def write_batch_options(bucket_name: str, file_name: str, parallelism: int, input_type: str,
                        input_path: str, config_path: str):
    batch_options = {
        "run_options": {
            "parallelism": parallelism,
            "max_run_duration": "7200s",
            "memory_mib": 512,
            "cpu_milli": 1000,
            "max_retry_count": 1,
        },
        "input_options": {
            "input_type": input_type,
            "input_list": f"gs://{bucket_name}/{input_path}",
            "config": config_path
        }
    }

    write_gcs_blob(bucket_name, file_name, json.dumps(batch_options, indent=2), 'application/json')


def get_args():
    # Read command line arguments
    args_parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        description="""
      Script to prepare configuration to run Dragen jobs.
      """,
        epilog="""
      Examples:

      python main.py -p 14 -b 320 -c gs://$PROJECT_ID-config/cram_config_378.json 
                -o gs://$PROJECT_ID-trigger/10K_3_7_8 -s gs://$PROJECT_ID-trigger/cram/input_list/10K_samples.txt
      """)

    args_parser.add_argument('-p', dest="parallelism",
                             help="how many tasks to run in parallel per single job", required=True)
    args_parser.add_argument('-b', dest="batch_size", type=int,
                             help="how many tasks in total in a single job (job runs non-stop till completion)", required=True)
    args_parser.add_argument('-c', dest="config_path_uri",
                             help="path to configuration file with Dragen and Jarvice options ", required=True,
                             action="append")
    args_parser.add_argument('-o', dest="out_dir",
                             help="path to the output GCS directory with all generated configurations", required=True)
    args_parser.add_argument('-s', dest="samples_input_uri",
                             help="path to the samples input list to be split into chunks for each job", required=True,
                             action="append")
    return args_parser


if __name__ == "__main__":
    parser = get_args()
    args = parser.parse_args()
    parallelism = args.parallelism
    batch_size = args.batch_size
    config_path = args.config_path_uri
    out_dir = args.out_dir
    samples_input = args.samples_input_uri

    assert len(config_path) == len(samples_input), f"Every configuration -c should have a corresponding -s samples" \
                                                   f" input option, however lents is not equal: config_path " \
                                                   f"{len(config_path)} samples_input {len(samples_input)}"
    doit(batch_size=batch_size, parallelism=parallelism, config_path=config_path,
         out_path=out_dir, samples_input=samples_input)
