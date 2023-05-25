DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PWD=$(pwd)
source "$DIR/SET"

DEST="gs://${INPUT_BUCKET}/"
echo "Triggering Pipeline for $DEST"
gsutil cp "${DIR}"/cloud_function/START_PIPELINE "${DEST}"
