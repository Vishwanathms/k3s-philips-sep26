#!/usr/bin/env bash
# Stage13 S2: build the runner image (if needed) and (re)start the
# self-hosted runner container. Needs a fresh REGISTRATION token from:
#   github.com/Vishwanathms/k3s-helm-argocd-capstone -> Settings -> Actions
#   -> Runners -> New self-hosted runner (Linux / x64) - copy the token
#   shown there (valid ~1h) and pass it as RUNNER_TOKEN. Only needed the
#   first time / after the runner volume is wiped - see entrypoint.sh.
set -euo pipefail

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_URL="https://github.com/Vishwanathms/k3s-helm-argocd-capstone"
IMAGE_NAME="capstone-gha-runner:local"
CONTAINER_NAME="capstone-gha-runner"

: "${RUNNER_TOKEN:?Usage: RUNNER_TOKEN=<token from GitHub Settings> $0}"

docker build -t "$IMAGE_NAME" "$STAGE_DIR/runner"

DOCKER_GID="$(stat -c '%g' /var/run/docker.sock)"

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

docker run -d --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  --network host \
  --group-add "$DOCKER_GID" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v capstone-runner-data:/home/runner \
  -e REPO_URL="$REPO_URL" \
  -e RUNNER_TOKEN="$RUNNER_TOKEN" \
  -e RUNNER_NAME="capstone-vm-runner" \
  -e RUNNER_LABELS="self-hosted,linux,x64,capstone" \
  "$IMAGE_NAME"

echo "Started. Logs: docker logs -f $CONTAINER_NAME"
