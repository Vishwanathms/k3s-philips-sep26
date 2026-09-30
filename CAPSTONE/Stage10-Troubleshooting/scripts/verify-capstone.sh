#!/usr/bin/env bash
# Student self-check: is the app actually healthy again?
# Passes only when all 5 faults are fixed - a Pod count that "looks fine"
# can still hide a wrong Service selector or a stuck rollout.
set -euo pipefail
NS=capstone
NODE_IP=$(hostname -I | awk '{print $1}')
fail=0

check() { printf '%-42s' "$1"; if eval "$2" >/dev/null 2>&1; then echo OK; else echo "FAIL"; fail=1; fi; }

check "web Service has endpoints"        "[ \"\$(kubectl -n $NS get endpoints web -o jsonpath='{.subsets}')\" != '' ]"
check "api rollout finished"             "kubectl -n $NS rollout status deployment/api --timeout=10s"
check "web rollout finished"             "kubectl -n $NS rollout status deployment/web --timeout=10s"
check "redis-0 not restarting"           "[ \"\$(kubectl -n $NS get pod redis-0 -o jsonpath='{.status.containerStatuses[0].restartCount}')\" = \"\$(kubectl -n $NS get pod redis-0 -o jsonpath='{.status.containerStatuses[0].restartCount}')\" ] && kubectl -n $NS get pod redis-0 | grep -q '2/2.*Running'"
check "all api/web Pods Ready"           "[ \"\$(kubectl -n $NS get pods -l 'app in (api,web)' --no-headers | grep -cv '2/2')\" = 0 ]"
check "counter reachable via Ingress"    "curl -sf -H 'Host: capstone.k3s.local' http://$NODE_IP/api/hits | grep -q hits"

echo
if [ "$fail" -eq 0 ]; then
  echo "== ALL CHECKS PASS - capstone is healthy"
else
  echo "== NOT YET - see the FAIL lines above"
  exit 1
fi
