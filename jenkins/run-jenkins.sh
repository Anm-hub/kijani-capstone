#!/usr/bin/env bash
# run-jenkins.sh - Builds and launches our custom Jenkins controller engine safely.
set -euo pipefail

echo "==== Initializing Automation Controller Storage Workspace ===="
JENKINS_HOME_HOST="${HOME}/jenkins_home"
mkdir -p "${JENKINS_HOME_HOST}"

# Safely chown to Jenkins user uid:gid inside the container boundaries
sudo chown -R 1000:1000 "${JENKINS_HOME_HOST}"

# Purge any stale container instances to prevent naming collision blocks
echo "Cleaning up duplicate automated controller instances..."
docker rm -f kijani-jenkins-automation 2>/dev/null || true

# Match host Docker group ID to prevent socket permission collision faults
DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)

echo "Building and launching Jenkins automation controller..."
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

echo "==== Jenkins Active. Access control center at http://localhost:8090 ===="

