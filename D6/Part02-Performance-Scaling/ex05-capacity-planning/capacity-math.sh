#!/usr/bin/env bash
# ex05 - compute a real capacity prediction from this node's CURRENT
# numbers, for a hypothetical Pod profile, then print the kubectl command
# to actually test the prediction (see verify-prediction.yaml / README.md).
set -euo pipefail

POD_CPU_M="${1:-250}"       # millicores requested per test Pod
POD_MEM_MI="${2:-256}"      # MiB requested per test Pod

ALLOC_CPU_M=$(kubectl get node -o jsonpath='{.items[0].status.allocatable.cpu}' | sed 's/[^0-9]*//g')
ALLOC_MEM_KI=$(kubectl get node -o jsonpath='{.items[0].status.allocatable.memory}' | sed 's/Ki//')
ALLOC_MEM_MI=$(( ALLOC_MEM_KI / 1024 ))

USED_CPU_M=$(kubectl describe node | awk '/Allocated resources/{f=1} f && /^  cpu /{print $2; exit}' | sed 's/m//')
USED_MEM_MI=$(kubectl describe node | awk '/Allocated resources/{f=1} f && /^  memory /{print $2; exit}' | sed 's/Mi//')

FREE_CPU_M=$(( ALLOC_CPU_M * 1000 - USED_CPU_M ))
FREE_MEM_MI=$(( ALLOC_MEM_MI - USED_MEM_MI ))

FIT_BY_CPU=$(( FREE_CPU_M / POD_CPU_M ))
FIT_BY_MEM=$(( FREE_MEM_MI / POD_MEM_MI ))

echo "Node allocatable:      ${ALLOC_CPU_M} CPU, ${ALLOC_MEM_MI}Mi memory"
echo "Already requested:     ${USED_CPU_M}m CPU, ${USED_MEM_MI}Mi memory  (kubectl describe node)"
echo "Free by request math:  ${FREE_CPU_M}m CPU, ${FREE_MEM_MI}Mi memory"
echo
echo "A Pod requesting ${POD_CPU_M}m CPU / ${POD_MEM_MI}Mi memory:"
echo "  fits ${FIT_BY_CPU} more times by CPU"
echo "  fits ${FIT_BY_MEM} more times by memory"
if [ "$FIT_BY_CPU" -le "$FIT_BY_MEM" ]; then
  echo "  -> CPU is the binding constraint: predict ${FIT_BY_CPU} Pods schedule, the next one(s) go Pending"
else
  echo "  -> Memory is the binding constraint: predict ${FIT_BY_MEM} Pods schedule, the next one(s) go Pending"
fi
