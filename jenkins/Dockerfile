# Copy the verified Docker CLI from the official docker image
FROM docker:cli AS docker-cli

FROM jenkins/jenkins:lts
USER root

# Inject the Docker CLI binary into the master root bin directory
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker

USER jenkins

# Automatically install all 5 required continuous integration orchestration plugins
RUN jenkins-plugin-cli --plugins docker-workflow ws-cleanup workflow-aggregator credentials-binding git

