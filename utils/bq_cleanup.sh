#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
bash "$DIR/../setup/check_setup.sh"
retVal=$?
if [ $retVal -eq 2 ]; then
  exit 2
fi

DELETE='DELETE FROM `'"${PROJECT_ID}"'`.'"${DATASET}."''"${TASK_STATUS_TABLE_ID}"' WHERE true; '

do_query()
{
  bq query  --nouse_legacy_sql \
  $DELETE
}

read -p "Are you sure you want to delete all BigQuery entries inside $PROJECT_ID.$DATASET.$TASK_STATUS_TABLE_ID? Press [y] if yes: " -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
  echo "Cleaning Up then..."
  do_query  2>/dev/null
fi


