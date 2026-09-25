# ex05 — Per-replica storage with `volumeClaimTemplates`

**What it shows:** a StatefulSet gives each replica its *own* PVC, created
automatically and named `<template>-<pod-name>` (`data-counter-0`,
`data-counter-1`). Deleting a Pod reattaches the **same** PVC to its
replacement — stable identity, not a fresh disk.

## Prerequisites

- A running k3s cluster and `kubectl`.
- The default `local-path` StorageClass (same as ex01) — the claim template
  sets no `storageClassName`, so it inherits the default.

No NFS and no extra drivers.

## Run

All paths are relative to `D4-Storage-/`.

```bash
kubectl apply -f ex05-statefulset-storage/namespace.yaml
kubectl apply -f ex05-statefulset-storage/statefulset.yaml
kubectl rollout status statefulset/counter -n d4-storage --timeout=90s

kubectl get pods -n d4-storage -l app=counter -o wide
kubectl get pvc -n d4-storage                  # one PVC per replica

# Each replica wrote its own identity to its own volume:
kubectl exec counter-0 -n d4-storage -- head -1 /data/identity.log
kubectl exec counter-1 -n d4-storage -- head -1 /data/identity.log
```

Prove the PVC follows the Pod identity:

```bash
kubectl delete pod counter-0 -n d4-storage --now
kubectl rollout status statefulset/counter -n d4-storage --timeout=90s

# The ORIGINAL first-boot line is still there - same PVC, not a new one:
kubectl exec counter-0 -n d4-storage -- cat /data/identity.log
```

## Clean up

```bash
kubectl delete -f ex05-statefulset-storage/statefulset.yaml --ignore-not-found

# volumeClaimTemplates PVCs are deliberately NOT deleted with the StatefulSet:
kubectl get pvc -n d4-storage
kubectl delete pvc data-counter-0 data-counter-1 -n d4-storage
```

They have to go by name: PVCs from a `volumeClaimTemplate` do not inherit the
Pod template's labels, so `-l app=counter` matches nothing. That they survive
the StatefulSet at all is the point — Kubernetes assumes stateful data is
worth keeping.

See [OUTPUT.md](OUTPUT.md) for a captured run.
