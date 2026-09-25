# ex01 — Dynamic provisioning with k3s `local-path`

**What it shows:** a PVC with no `storageClassName` falls through to the
cluster default (`local-path`), stays `Pending` until a Pod consumes it
(`WaitForFirstConsumer`), and the data survives deleting the Pod.

## Prerequisites

- A running k3s cluster and a working `kubectl` (`kubectl get nodes`).
- The bundled `local-path` StorageClass, marked default:
  `kubectl get sc` → `local-path (default) rancher.io/local-path`.

Nothing else. No NFS, no extra drivers.

## Run

All paths are relative to `D4-Storage-/`.

```bash
kubectl apply -f ex01-local-path-dynamic/namespace.yaml
kubectl apply -f ex01-local-path-dynamic/pvc.yaml

# Deliberately Pending - no consumer yet:
kubectl get pvc data-claim -n d4-storage

kubectl apply -f ex01-local-path-dynamic/pod.yaml
kubectl wait --for=condition=Ready pod/writer -n d4-storage --timeout=60s

# Now Bound, with a PV that did not exist a moment ago:
kubectl get pvc data-claim -n d4-storage
kubectl get pv
kubectl exec writer -n d4-storage -- cat /data/log
```

Prove persistence across a Pod restart:

```bash
kubectl delete pod writer -n d4-storage --now
kubectl apply -f ex01-local-path-dynamic/pod.yaml
kubectl wait --for=condition=Ready pod/writer -n d4-storage --timeout=60s
kubectl exec writer -n d4-storage -- cat /data/log   # old lines still there
```

## Clean up

```bash
kubectl delete -f ex01-local-path-dynamic/pod.yaml --ignore-not-found
kubectl delete -f ex01-local-path-dynamic/pvc.yaml --ignore-not-found
```

Deleting the PVC also deletes the PV and the node directory — `local-path`'s
reclaim policy is `Delete`. Compare with ex02, which uses `Retain`.

See [OUTPUT.md](OUTPUT.md) for a captured run.
