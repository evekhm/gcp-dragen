DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PWD=$(pwd)
source "$DIR/SET"
echo "Triggering Pipeline for $PROJECT_ID"
gsutil cp "${DIR}"/cloud_function/START_PIPELINE "gs://${INPUT_BUCKET}/"
