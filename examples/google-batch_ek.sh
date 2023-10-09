#!/bin/bash
WDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${WDIR}"/../setup/init_env_vars.sh

suffix=$(echo $RANDOM | md5sum | head -c 8)

#      "taskEnvironments": [
#          {
#              "variables": {
#                  "COMMAND": "echo Hello \${TASK_VARIABLE_NAME}! This is task \${BATCH_TASK_INDEX}. This job has a total of \${BATCH_TASK_COUNT} tasks"
#              }
#          },
#          {
#              "variables": {
#                  "COMMAND": "echo Hello \${TASK_VARIABLE_NAME}! This is task \${BATCH_TASK_INDEX}. This job has a total of \${BATCH_TASK_COUNT} tasks"
#              }
#          },
#          {
#              "variables": {
#                  "COMMAND": "echo Hello \${TASK_VARIABLE_NAME}! This is task \${BATCH_TASK_INDEX}. This job has a total of \${BATCH_TASK_COUNT} tasks"
#              }
#          }
#      ],

JOBNAME="$JOB_NAME_SHORT-$suffix"

echo "Submitting $JOBNAME"
gcloud batch jobs submit "$JOBNAME" --network="projects/$PROJECT_ID/global/networks/$GCLOUD_NETWORK" --location $GCLOUD_REGION  --subnetwork="projects/$PROJECT_ID/regions/${GCLOUD_REGION}/subnetworks/$GCLOUD_SUBNET" --config - <<EOD
{
  "name": "$JOBNAME",
  "notifications": [
      {
          "message": {
              "type": "TASK_STATE_CHANGED"
          },
          "pubsubTopic":  "projects/$PROJECT_ID/topics/job-dragen-task-state-change-topic"
      },
      {
          "message": {
              "type": "JOB_STATE_CHANGED"
          },
          "pubsubTopic":  "projects/$PROJECT_ID/topics/job-dragen-job-state-change-topic"
      }
  ],
  "taskGroups": [
    {
      "taskCount": "7",
      "parallelism": "3",
      "taskSpec": {
        "computeResource": {
          "cpuMilli": "1000",
          "memoryMib": "512"
        },
        "runnables": [
          {
            "script": {
              "text": "if [ \$((BATCH_TASK_INDEX % 5)) -eq 0 ]; then exit 1; else echo \"The index is \${BATCH_TASK_INDEX}\"; exit 0; fi"
            }
          }
        ]
        ,
        "volumes": []
      }
    }
  ],
  "allocationPolicy": {
    "serviceAccount": {
        "email": "${JOB_SERVICE_ACCOUNT}"
    },
    "instances": [
      {
        "policy": {
          "provisioningModel": "STANDARD",
          "machineType": "e2-micro"
        }
      }
    ]
  },
  "logsPolicy": {
    "destination": "CLOUD_LOGGING"
  }
}
EOD





