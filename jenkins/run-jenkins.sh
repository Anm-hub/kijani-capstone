#!/usr/bin/env bash
# run-jenkins.sh - Builds and launches our custom Jenkins controller engine
set -euo pipefail

echo "Checking system memory layout limits..."
free -h

JENKINS_HOME_HOST="${HOME}/jenkins_home"
mkdir -p "${JENKINS_HOME_HOST}"

# Match host Docker group ID to prevent socket permission collision faults
DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)

echo "Spinning up Jenkins controller engine container on port 8090..."
docker build -t kijani-jenkins-controller ./jenkins

docker run -d \
  --name kijani-jenkins-automation \
  -p 8090:8080 \
  -p 50000:50000 \
  -v "${JENKINS_HOME_HOST}:${JENKINS_HOME_HOST}" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e JENKINS_HOME="${JENKINS_HOME_HOST}" \
  --group-add "${DOCKER_GID}" \
  --restart unless-stopped \
  kijani-jenkins-controller

echo "Jenkins container is active. Access web control center at http://localhost:8090"
