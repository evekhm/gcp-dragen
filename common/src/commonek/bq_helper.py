"""
Copyright 2022 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""
from typing import List, Dict
from commonek.logging import Logger
from google.cloud import bigquery

bigquery_client = bigquery.Client()


def stream_data_to_bigquery(rows_to_insert: List[Dict], table_id: str):
    try:
        Logger.info(
            f"stream_data_to_bigquery table_id={table_id}, rows_to_insert={rows_to_insert}"
        )
        errors = bigquery_client.insert_rows_json(table_id, rows_to_insert)

        return errors
    except Exception as exc:
        Logger.error(f"stream_data_to_bigquery - failed with {exc}")
        return [{"errors": exc}]


def run_query(sql: str):
    try:
        Logger.info(
            f"run_query with sql={sql}"
        )
        query_config = bigquery.QueryJobConfig(use_legacy_sql=False)
        query_job = bigquery_client.query(sql, job_config=query_config)
        return query_job.result()
    except Exception as exc:
        Logger.error(f"run_query - failed with {exc}")
        return None
