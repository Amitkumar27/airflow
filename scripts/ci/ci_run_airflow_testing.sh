#!/usr/bin/env bash

#
#  Licensed to the Apache Software Foundation (ASF) under one
#  or more contributor license agreements.  See the NOTICE file
#  distributed with this work for additional information
#  regarding copyright ownership.  The ASF licenses this file
#  to you under the Apache License, Version 2.0 (the
#  "License"); you may not use this file except in compliance
#  with the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing,
#  software distributed under the License is distributed on an
#  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#  KIND, either express or implied.  See the License for the
#  specific language governing permissions and limitations
#  under the License.

set -euo pipefail
MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck source=./_check_not_in_container.sh
. "${MY_DIR}/_check_not_in_container.sh"
# shellcheck source=./_check_coreutils.sh
. "${MY_DIR}"/_check_coreutils.sh

pushd "${MY_DIR}/../../" &>/dev/null || exit 1

export VERBOSE=${VERBOSE:="true"}

if [[ ${VERBOSE} == "true" ]]; then
    set -x
else
    echo
    echo "Running the scripts without verbose output"
    echo "You can increase verbosity by running 'export VERBOSE=true'"
    echo
fi

export PYTHON_VERSION=${PYTHON_VERSION:=$(python -c \
    'import sys; print("%s.%s" % (sys.version_info.major, sys.version_info.minor))')}
AIRFLOW_VERSION=$(cat airflow/version.py - << EOF | python
print(version.replace("+",""))
EOF
)
export AIRFLOW_VERSION

export DOCKERHUB_USER=${DOCKERHUB_USER:="apache"}
export DOCKERHUB_REPO=${DOCKERHUB_REPO:="airflow"}
export BACKEND=${BACKEND:="sqlite"}
export ENV=${ENV:="docker"}
export MOUNT_LOCAL_SOURCES=${MOUNT_LOCAL_SOURCES:="false"}
export WEBSERVER_HOST_PORT=${WEBSERVER_HOST_PORT:="8080"}
export AIRFLOW_CI_VERBOSE=${VERBOSE}

if [[ ${MOUNT_LOCAL_SOURCES} == "true" ]]; then
    DOCKER_COMPOSE_LOCAL=("-f" "${MY_DIR}/docker-compose-local.yml")
else
    DOCKER_COMPOSE_LOCAL=()
fi

# Branch name to download image from
# Can be overridden by SOURCE_BRANCH
# Define an empty BRANCH_NAME_FIRST
export AIRFLOW_CONTAINER_BRANCH_NAME=${AIRFLOW_CONTAINER_BRANCH_NAME:=""}
# in case SOURCE_BRANCH is defined it can override the BRANCH_NAME
# TODO: Remove me - it's only needed before we merge to master
export AIRFLOW_CONTAINER_BRANCH_NAME=\
${AIRFLOW_CONTAINER_SOURCE_BRANCH_OVERRIDE:=${AIRFLOW_CONTAINER_BRANCH_NAME}}
# Default branch name for triggered builds is master
export AIRFLOW_CONTAINER_BRANCH_NAME=${AIRFLOW_CONTAINER_BRANCH_NAME:="master"}

export AIRFLOW_CONTAINER_DOCKER_IMAGE=\
${DOCKERHUB_USER}/${DOCKERHUB_REPO}:${AIRFLOW_CONTAINER_BRANCH_NAME}-python${PYTHON_VERSION}-ci


echo
echo "Using docker image: ${AIRFLOW_CONTAINER_DOCKER_IMAGE} for docker compose runs"
echo

set +u
if [[ "${ENV}" == "docker" ]]; then
  docker-compose --log-level INFO \
      -f "${MY_DIR}/docker-compose.yml" \
      -f "${MY_DIR}/docker-compose-${BACKEND}.yml" \
      "${DOCKER_COMPOSE_LOCAL[@]}" \
        run airflow-testing /opt/airflow/scripts/ci/in_container/entrypoint_ci.sh;
else
  "${MY_DIR}/kubernetes/minikube/stop_minikube.sh" && "${MY_DIR}/kubernetes/setup_kubernetes.sh" && \
    "${MY_DIR}/kubernetes/kube/deploy.sh" -d persistent_mode
  MINIKUBE_IP=$(minikube ip)
  export MINIKUBE_IP
  docker-compose --log-level ERROR \
      -f "${MY_DIR}/docker-compose.yml" \
      -f "${MY_DIR}/docker-compose-${BACKEND}.yml" \
      -f "${MY_DIR}/docker-compose-kubernetes.yml" \
      "${DOCKER_COMPOSE_LOCAL[@]}" \
         run --no-deps airflow-testing /opt/airflow/scripts/ci/in_container/entrypoint_ci.sh;
  set +x
  "${MY_DIR}/kubernetes/minikube/stop_minikube.sh"

  "${MY_DIR}/kubernetes/minikube/stop_minikube.sh" && "${MY_DIR}/kubernetes/setup_kubernetes.sh" && \
    "${MY_DIR}/kubernetes/kube/deploy.sh" -d git_mode
  MINIKUBE_IP=$(minikube ip)
  export MINIKUBE_IP
  docker-compose --log-level ERROR \
      -f "${MY_DIR}/docker-compose.yml" \
      -f "${MY_DIR}/docker-compose-${BACKEND}.yml" \
      -f "${MY_DIR}/docker-compose-kubernetes.yml" \
      "${DOCKER_COMPOSE_LOCAL[@]}" \
         run --no-deps airflow-testing /opt/airflow/scripts/ci/in_container/entrypoint_ci.sh;
  "${MY_DIR}/kubernetes/minikube/stop_minikube.sh"
fi
set -u

popd &>/dev/null || exit 1

if [[ ${VERBOSE} == "true" ]]; then
    set +x
fi
