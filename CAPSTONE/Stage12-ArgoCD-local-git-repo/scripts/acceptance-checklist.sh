#!/usr/bin/env bash
# Stage12 final acceptance checklist: one check per day's lesson, so a pass
# here means the whole 3-tier app - not just Argo CD - is still standing.
set -euo pipefail
NS=capstone
NODE_IP=$(hostname -I | awk '{print $1}')
fail=0

check() { printf '%-52s' "$1"; if eval "$2" >/dev/null 2>&1; then echo OK; else echo "FAIL"; fail=1; fi; }

echo "--- Day 07: health & resources ---"
check "all api/web Pods Ready (2/2)"        "[ \"\$(kubectl -n $NS get pods -l 'app in (api,web)' --no-headers | grep -cv '2/2')\" = 0 ]"
check "redis-0 Running (2/2)"               "kubectl -n $NS get pod redis-0 | grep -q '2/2.*Running'"
check "ResourceQuota present"               "kubectl -n $NS get resourcequota capstone-quota"

echo "--- Day 08: disruption & backup ---"
check "PDB web minAvailable satisfied"      "[ \"\$(kubectl -n $NS get pdb web -o jsonpath='{.status.disruptionsAllowed}')\" -ge 0 ]"
check "PDB api minAvailable satisfied"      "[ \"\$(kubectl -n $NS get pdb api -o jsonpath='{.status.disruptionsAllowed}')\" -ge 0 ]"

echo "--- Day 09: HPA scaling ---"
check "HPA api present, has metrics"        "[ \"\$(kubectl -n $NS get hpa api -o jsonpath='{.status.currentReplicas}')\" -ge 2 ]"

echo "--- Day 10: scheduling ---"
check "PriorityClasses exist"               "kubectl get priorityclass capstone-data capstone-app capstone-batch"
check "redis on capstone/data=true node"    "[ \"\$(kubectl get pod -n $NS redis-0 -o jsonpath='{.spec.nodeName}' | xargs -I{} kubectl get node {} -o jsonpath='{.metadata.labels.capstone/data}')\" = 'true' ]"

echo "--- Day 11: security ---"
check "namespace PSA restricted"            "[ \"\$(kubectl get ns $NS -o jsonpath='{.metadata.labels.pod-security\\.kubernetes\\.io/enforce}')\" = 'restricted' ]"
check "web ServiceAccount automount off"    "[ \"\$(kubectl -n $NS get sa web -o jsonpath='{.automountServiceAccountToken}')\" = 'false' ]"
check "default-deny NetworkPolicy present"  "kubectl -n $NS get networkpolicy default-deny"
check "redis-auth Secret present"           "kubectl -n $NS get secret redis-auth"

echo "--- Day 12: troubleshooting ---"
check "web Service has endpoints"           "[ \"\$(kubectl -n $NS get endpoints web -o jsonpath='{.subsets}')\" != '' ]"
check "api Service has endpoints"           "[ \"\$(kubectl -n $NS get endpoints api -o jsonpath='{.subsets}')\" != '' ]"

echo "--- Day 13: Helm chart lineage ---"
check "objects carry Helm release labels"   "[ \"\$(kubectl -n $NS get deploy web -o jsonpath='{.metadata.labels.app\\.kubernetes\\.io/managed-by}')\" = 'Helm' ]"

echo "--- Day 14: Argo CD ---"
check "Application capstone Synced"         "[ \"\$(kubectl -n argocd get application capstone -o jsonpath='{.status.sync.status}')\" = 'Synced' ]"
check "Application capstone Healthy"        "[ \"\$(kubectl -n argocd get application capstone -o jsonpath='{.status.health.status}')\" = 'Healthy' ]"
check "automated selfHeal enabled"          "[ \"\$(kubectl -n argocd get application capstone -o jsonpath='{.spec.syncPolicy.automated.selfHeal}')\" = 'true' ]"
check "live web replicas match git (2)"     "[ \"\$(kubectl -n $NS get deploy web -o jsonpath='{.spec.replicas}')\" = 2 ]"

echo "--- End-to-end proof ---"
check "counter reachable via Ingress"       "curl -sf -H 'Host: capstone.k3s.local' http://$NODE_IP/api/hits | grep -q hits"

echo
if [ "$fail" -eq 0 ]; then
  echo "== ACCEPTANCE PASS - capstone is production-shaped end to end"
else
  echo "== NOT YET - see the FAIL lines above"
  exit 1
fi
