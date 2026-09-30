# Capstone Stage 13: a self-hosted GitHub Actions runner as a container on
# this VM. It only has the Docker CLI, not a daemon - the run script (see
# ../scripts/run-runner.sh) mounts the VM's own /var/run/docker.sock, so a
# `docker build`/`docker push` step in the workflow is actually executed by
# the same Docker daemon Stage00's registry container runs in. That's also
# why the workflow's `docker push localhost:5000/...` just works: the
# daemon doing the push runs on the VM itself, so "localhost" is the VM.
FROM ubuntu:24.04

ARG RUNNER_VERSION=2.337.0
ARG YQ_VERSION=v4.54.1

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates tar git jq sudo docker.io \
    && rm -rf /var/lib/apt/lists/*

# yq: used by the workflow to bump chart/capstone/values.yaml's two image
# tags precisely (by key path), instead of a fragile sed/grep pattern.
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
      -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

RUN useradd -m runner && usermod -aG sudo,docker runner

WORKDIR /home/runner
RUN curl -fsSL -o actions-runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    && tar xzf actions-runner.tar.gz && rm actions-runner.tar.gz \
    && ./bin/installdependencies.sh \
    && chown -R runner:runner /home/runner

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER runner
ENTRYPOINT ["/entrypoint.sh"]
