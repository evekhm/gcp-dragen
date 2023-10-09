DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DIR}/init_env_vars.sh"

SLACK_WEB_HOOK=$1

usage()
{
    echo "Usage: $0 <webhook_url>"
    exit 2
}

if [ -z "$SLACK_WEB_HOOK" ]; then
  usage
fi

function create_secret(){
  secret_name=$1
  secret_value=$2
  exists=$(gcloud secrets describe "${secret_name}" 2> /dev/null)
  if [ -z "$exists" ]; then
    echo "Creating $secret_name secret..."
    printf "$secret_value" | gcloud secrets create "$secret_name" --replication-policy="user-managed" --project $PROJECT_ID  --data-file=-  --locations=$GCLOUD_REGION
  fi

}

create_secret $SLACK_WEB_HOOK_SECRET_NAME "$SLACK_WEB_HOOK"