#!/usr/bin/env bash
# Registers this container as a self-hosted runner on first start (needs a
# fresh REGISTRATION token from GitHub - RUNNER_TOKEN - valid ~1h), then
# just runs. /home/runner is a named volume (see run-runner.sh), so
# .runner/.credentials survive `docker restart`; the token is only needed
# again if the volume is wiped or the runner is re-registered.
set -euo pipefail

cd /home/runner

cleanup() {
  echo "Caught stop signal, deregistering runner..."
  ./config.sh remove --unattended --token "${RUNNER_TOKEN:-}" || true
}
trap cleanup INT TERM

if [ ! -f .runner ]; then
  : "${REPO_URL:?REPO_URL not set}"
  : "${RUNNER_TOKEN:?RUNNER_TOKEN not set (get a fresh one from GitHub - Settings - Actions - Runners - New self-hosted runner)}"
  ./config.sh --unattended \
    --url "$REPO_URL" \
    --token "$RUNNER_TOKEN" \
    --name "${RUNNER_NAME:-capstone-vm-runner}" \
    --labels "${RUNNER_LABELS:-self-hosted,linux,x64,capstone}" \
    --work "${RUNNER_WORKDIR:-_work}" \
    --replace
else
  echo "Already registered (found .runner in the persisted volume), skipping config.sh"
fi

./run.sh &
wait $!
