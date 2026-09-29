#!/usr/bin/env bash
# Evict ONE Pod through the Eviction API, the same call `kubectl drain`
# makes for every Pod on a node. Unlike `kubectl delete pod`, an eviction
# is checked against PodDisruptionBudgets and can be refused (HTTP 429).
#
# usage: evict.sh <namespace> <pod>
set -euo pipefail
ns=${1:?namespace}; pod=${2:?pod}
kubectl create --raw "/api/v1/namespaces/$ns/pods/$pod/eviction" -f - <<JSON
{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"$pod","namespace":"$ns"}}
JSON
echo
