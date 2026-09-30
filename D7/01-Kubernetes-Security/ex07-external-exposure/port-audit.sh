#!/usr/bin/env bash
# Real external-exposure audit for this node: every port listening on
# 0.0.0.0/[::] (i.e. reachable from OTHER machines, not just localhost),
# cross-referenced against the host firewall's actual state.
set -euo pipefail

echo "== Firewall status =="
sudo ufw status verbose || true

echo
echo "== Ports listening on ALL interfaces (0.0.0.0 / [::], excluding loopback) =="
sudo ss -tlnp | awk 'NR==1 || ($4 !~ /^127\./ && $4 !~ /^\[::1\]/)'

echo
echo "== Unauthenticated access checks =="
printf "kubelet API (10250):     "
curl -sk https://192.168.230.103:10250/pods -o /dev/null -w "%{http_code}\n"
printf "kube-apiserver (6443):   "
curl -sk https://192.168.230.103:6443/api/v1/secrets -o /dev/null -w "%{http_code}\n"
printf "Traefik (80):            "
curl -sk http://192.168.230.103:80 -o /dev/null -w "%{http_code}\n"
