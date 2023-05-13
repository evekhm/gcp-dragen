#!/bin/bash
date_str=$(date +%s )
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}"/SET
JOB_NAME_UID="projects/${PROJECT_ID}/locations/${GCLOUD_REGION}/jobs/test-batch-${date_str}"
echo "Submitting $JOB_NAME_UID"
gcloud beta batch jobs submit "$JOB_NAME_UID" --network="projects/$PROJECT_ID/global/networks/$GCLOUD_NETWORK" --subnetwork="projects/$PROJECT_ID/regions/${GCLOUD_REGION}/subnetworks/$GCLOUD_SUBNET" --config - <<EOD
{
   "name": "$JOB_NAME_UID",
    "taskGroups": [
        {
            "taskSpec": {
                "runnables": [
                    {
                        "container": {
                            "imageUri": "gcr.io/google-containers/busybox",
                            "entrypoint": "/bin/sh",
                            "commands": [
                                "-c",
                                "echo Hello world! This is task ${BATCH_TASK_INDEX}. This job has a total of ${BATCH_TASK_COUNT} tasks."
                            ]
                        }
                    }
                ],
                "computeResource": {
                  "cpuMilli": "1000",
                  "memoryMib": "512"
                },
                "maxRetryCount": 2,
                "maxRunDuration": "3600s"
            },
            "taskCount": 1,
            "parallelism": 1
        }
    ],
    "allocationPolicy": {
      "serviceAccount": {
          "email": "${SA_JOB_EMAIL}"
      },
      "instances": [
        {
          "policy": {
            "provisioningModel": "STANDARD",
            "machineType": "${GCLOUD_MACHINE}"
          }
        }
      ]
    },
    "logsPolicy": {
      "destination": "CLOUD_LOGGING"
    }
}
EOD

echo "Commands to manage the jobs:"
echo "gcloud beta batch jobs describe $JOB_NAME_UID"
echo "gcloud beta batch jobs delete $JOB_NAME_UID"
echo "gcloud beta batch jobs list"

