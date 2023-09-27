#!/bin/bash
WDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${WDIR}"/../setup/init_env_vars.sh
"${WDIR}"/prepare.sh

JARVICE_API_URL="https://illumina.nimbix.net/api"
JARVICE_MACHINE_TYPE=nx1
# Google Batch (https://cloud.google.com/batch) jobname

# optional environment file
source env.sh

# no edits required past this line

GCLOUD=$(type -p gcloud)
if [ -z "$GCLOUD" ]; then
    cat <<EOF
Could not find 'gcloud' in PATH. It may not be installed.
EOF
  exit 1
fi

JQ=$(type -p jq)
if [ -z "$JQ" ]; then
    cat <<EOF
Could not find 'jq' in PATH. It may not be installed.
EOF
  exit 1
fi

suffix=$(echo $RANDOM | md5sum | head -c 8)

JOBNAME="$NAME-$suffix"

batch_json=$(cat <<EOD
{
  "name": "projects/$PROJECT_ID/locations/$ZONE/jobs/$JOBNAME",
  "taskGroups": [
    {
      "taskCount": "1",
      "parallelism": "1",
      "taskSpec": {
        "computeResource": {
          "cpuMilli": "1000",
          "memoryMib": "512"
        },
        "runnables": [
          {
            "environment": {
              "secretVariables": {
                "JARVICE_API_USER": "$JARVICE_API_USERNAME_SECRET",
                "JARVICE_API_KEY": "$JARVICE_API_APIKEY_SECRET",
                "S3_ACCESS_KEY": "$S3_ACCESS_KEY_SECRET",
                "S3_SECRET_KEY": "$S3_SECRET_KEY_SECRET",
                "ILLUMINA_LIC_SERVER": "$ILLUMINA_LIC_SERVER_SECRET"
              }
            },
            "container": {
              "imageUri": "us-docker.pkg.dev/jarvice/images/jarvice-dragen-service:$VERSION",
              "entrypoint": "/usr/local/bin/entrypoint",
              "commands": [
	              "--api-host", "$JARVICE_API_URL",
	              "--machine", "$JARVICE_MACHINE_TYPE",
	              "--dragen-app", "$JARVICE_DRAGEN_APP",
                "--google-sa", "$SERVICE_ACCOUNT",
	              "--"
              ],
              "volumes": []
            }
          }
        ],
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
)

for str in ${DRAGEN_ARGS[@]}; do
  batch_json=$(echo $batch_json | $JQ --arg arg "$str" '.taskGroups[0].taskSpec.runnables[0].container.commands[.taskGroups[0].taskSpec.runnables[0].container.commands | length] |= . + $arg');
done

echo $batch_json | $GCLOUD batch jobs submit  --project $PROJECT_ID $JOBNAME --location $ZONE --network="projects/$PROJECT_ID/global/networks/$GCLOUD_NETWORK" --subnetwork="projects/$PROJECT_ID/regions/${GCLOUD_REGION}/subnetworks/$GCLOUD_SUBNET"  --config -

