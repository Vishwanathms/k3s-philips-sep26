#!/usr/bin/env bash
# Stops and removes the runner container (deregisters via entrypoint.sh's
# trap) and drops the persisted volume, so the next run-runner.sh start
# is a clean first-time registration again.
set -euo pipefail

docker rm -f -t 30 capstone-gha-runner >/dev/null 2>&1 || true
docker volume rm capstone-runner-data >/dev/null 2>&1 || true
echo "Runner container and volume removed."
