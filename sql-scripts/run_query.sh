#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR/../setup/init_env_vars.sh" > /dev/null 2>&1

SCRIPT=$1
SAMPLE_ID=$2

if [ -z "$SCRIPT" ]; then
  echo " Usage: ./run_query.sh QUERY_NAME"
  echo " Options:"
  echo "     - count   - Summary of the samples with counts per status "
  echo "     - samples - Detailed summary of samples with the latest statuses"
  echo "     - sample [SAMPLE_ID] - Detailed info per sample"
  echo "     - delete  - Cleans up the table"
  exit
fi


FILTER="--parameter=SAMPLE_ID:STRING:$SAMPLE_ID"
#echo "Running $SCRIPT"
bq query --project_id="$PROJECT_ID" --dataset_id=$DATASET --nouse_legacy_sql "$FILTER" --max_rows=10000 --flagfile="${DIR}/${SCRIPT}.sql"  2> /dev/null

#f=$( cat "${DIR}/${SCRIPT}.sql" )
#bq query --project_id="$PROJECT_ID" --dataset_id=$BIGQUERY_DATASET --nouse_legacy_sql "$FILTER" "$f"   2> /dev/null


#./run_query.sh query_extraction_confidence.sql
#./run_query.sh diagnose.sql

