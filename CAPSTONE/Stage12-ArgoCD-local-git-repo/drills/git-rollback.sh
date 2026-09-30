#!/usr/bin/env bash
# D2: ship a bad release through git, watch Argo CD sync it and go
# Degraded/Progressing, then roll back with `git revert` - not
# `helm rollback`. Once Argo CD owns the release, git history is the
# rollback mechanism.
set -euo pipefail
CLONE_DIR="$HOME/capstone-gitops-clone"
cd "$CLONE_DIR"
git pull --ff-only origin main

echo "-- breaking: api image tag -> a tag that was never pushed --"
sed -i '0,/tag: "1.0.0"/s//tag: "1.0.0-does-not-exist"/' chart/capstone/values.yaml
git commit -am "drill: bump api image to a bad tag"
git push origin main
kubectl -n argocd annotate application capstone argocd.argoproj.io/refresh=hard --overwrite
sleep 10

echo "-- watch it go bad (new api Pod should be ImagePullBackOff, old Pods still serving) --"
kubectl -n capstone get pods -l tier=api
kubectl -n argocd get application capstone -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'
echo "-- counter still answers through the OLD api Pods --"
curl -sf -H 'Host: capstone.k3s.local' "http://$(hostname -I | awk '{print $1}')/api/hits"; echo

echo
echo "-- rolling back: git revert, not helm rollback --"
git revert --no-edit HEAD
git push origin main
kubectl -n argocd annotate application capstone argocd.argoproj.io/refresh=hard --overwrite
sleep 10

echo "-- recovered --"
kubectl -n capstone get pods -l tier=api
kubectl -n argocd get application capstone -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'
