#!/bin/bash
# Copyright 2018 Google LLC
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
set -ex

SCRIPT_DIR=$(dirname "$0")
REPO_DIR=$(realpath "${SCRIPT_DIR}/..")

# Set up
cd "${REPO_DIR}"


# These programs need to be already installed
progs=(docker docker-compose curl)
for p in "${progs[@]}"
do
  command -v "$p" > /dev/null 2>&1 || \
    { echo >&2 "$p is required but not installed. Aborting."; exit 1; }
done

##########################################################
# Step 1: Run all unit tests
##########################################################
echo -e "\n[Running] Basic test #1 - Runnning unit tests"
# Run jsunit tests
docker-compose build jsunit-test
docker run --rm grpcweb/jsunit-test /bin/bash \
    /grpc-web/scripts/docker-run-jsunit-tests.sh

# Run (mocha) unit tests
docker-compose build prereqs
docker run --rm grpcweb/prereqs /bin/bash \
  /github/grpc-web/scripts/docker-run-mocha-tests.sh


##########################################################
# Step 2: Test echo server
##########################################################
echo -e "\n[Running] Basic test #2 - Testing echo server"
docker-compose build prereqs envoy node-server

# Bring up the Echo server and the Envoy proxy (in background).
# The 'sleep' seems necessary for the docker containers to be fully up
# and listening before we test the with curl requests
docker-compose up -d node-server envoy && sleep 5;

# Run a curl request and verify the output
source ./scripts/test-proxy.sh

# Remove all docker containers
docker-compose down


##########################################################
# Step 3: Test all Dockerfile and Bazel targets can build!
##########################################################
echo -e "\n[Running] Basic test #3 - Testing everything buids"
if [[ "$MASTER" == "1" ]]; then
  # Build all for continuous_integration
  # docker-compose build

  # Temporary fix `protoc-plugin` build failure (introduced in
  # https://github.com/grpc/grpc-web/pull/1445) by building
  # everything but it.
  # TODO: Revert to building all targets.
  docker-compose build prereqs echo-server node-server node-interop-server envoy grpcwebproxy commonjs-client closure-client ts-client binary-client interop-client jsunit-test
else
  # Only build a subset of docker images for presubmit runs
  docker-compose build commonjs-client closure-client ts-client
fi

# Run build tests to ensure all Bazel targets can build.
docker run --rm grpcweb/prereqs /bin/bash \
  /github/grpc-web/scripts/docker-run-build-tests.sh

# Clean up
git clean -f -d -x
echo 'Basic tests completed successfully!'
