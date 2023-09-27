#!/bin/bash
# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
printf="$CDIR/../utils/print"
source "${CDIR}"/init_env_vars.sh  > /dev/null 2>&1

function build_common_package(){
  exists=$(gcloud artifacts repositories describe --location="${GCLOUD_REGION}" "${ARTIFACTS_REPO}" 2> /dev/null)
  if [ -z "$exists" ]; then
    $printf "Creating ${ARTIFACTS_REPO} repo ..."
    gcloud artifacts repositories create "${ARTIFACTS_REPO}" \
      --repository-format=python \
      --location="${GCLOUD_REGION}" \
      --description="Python package repository"
  else
    $printf "Repository ${ARTIFACTS_REPO} already exists ..."  INFO
  fi

  package_exists=$(gcloud artifacts packages describe --location=${GCLOUD_REGION} --repository=${ARTIFACTS_REPO}  ${COMMON_PACKAGE_NAME} 2> /dev/null)
  if [ -n "$package_exists" ]; then
    #check for version
    version_exists=$(gcloud artifacts versions describe "${COMMON_PACKAGE_VERSION}" --package="${COMMON_PACKAGE_NAME}" --location=${GCLOUD_REGION} --repository=${ARTIFACTS_REPO} --format='value(name)' 2> /dev/null)
  fi

  if [ -n "$version_exists" ]; then
        gcloud artifacts versions delete "${COMMON_PACKAGE_VERSION}" --package="${COMMON_PACKAGE_NAME}" --location=${GCLOUD_REGION}  --repository=${ARTIFACTS_REPO} --quiet
        version_exists=""
  fi

  if [ -z "$version_exists" ]; then
    # Will build, so first clean up directory
    rm "${CDIR}/../common/dist/*" 2> /dev/null
    $printf "Building package ${COMMON_PACKAGE_NAME} with version=${COMMON_PACKAGE_VERSION} ..."
    python3 -m venv env
    source env/bin/activate
    python3 -m pip install --upgrade build
    pip3 install twine
    PWD=$(pwd)
    cd "${CDIR}"/../common || exit
    python3 -m build

    pip3 install keyring
    pip3 install keyrings.google-artifactregistry-auth

  #  python3 -m twine upload --repository-url https://${GCLOUD_REGION}-python.pkg.dev/${PROJECT_ID}/${ARTIFACTS_REPO}/ "${DIR}"/dist/*
  #  python3 -m twine upload --repository-url https://${GCLOUD_REGION}-python.pkg.dev/${PROJECT_ID}/${ARTIFACTS_REPO}/ dist/*
    $printf "Uploading ${COMMON_PACKAGE_NAME} with version=${COMMON_PACKAGE_VERSION} to ${ARTIFACTS_REPO} ..."
    gcloud builds submit --config=cloudbuild.yaml \
      --substitutions=_LOCATION=${GCLOUD_REGION},_REPOSITORY=${ARTIFACTS_REPO} .
    cd "${PWD}" || exit
  else
      $printf "Package ${COMMON_PACKAGE_NAME} with version=${COMMON_PACKAGE_VERSION} already exists in ${ARTIFACTS_REPO}."  INFO
  fi

  # gcloud auth application-default login
  #gcloud artifacts print-settings python \
  #>     --project=$PROJECT_ID \
  #>     --repository=${ARTIFACTS_REPO} \
  #>     --location=${GCLOUD_REGION}
}

build_common_package