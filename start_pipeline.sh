DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PWD=$(pwd)
source "$DIR/SET"

FOLDER=$1
if [ -z "$FOLDER" ]; then
  DEST="gs://${INPUT_BUCKET}/"
else
  DEST="gs://${INPUT_BUCKET}/${FOLDER}/"
fi

echo "Triggering Pipeline for $DEST"
gsutil cp "${DIR}"/cloud_function/START_PIPELINE "${DEST}"
