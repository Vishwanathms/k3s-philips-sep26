# ex02 — Static provisioning with a hand-made hostPath PV

**What it shows:** an admin creates the PersistentVolume ahead of any claim.
Binding happens because the PVC and PV agree on `storageClassName: manual` —
there is no provisioner called `manual`. Reclaim policy is `Retain`, so the
data outlives the claim, and the `Released` PV cannot be reused as-is.

## Prerequisites

- A running k3s cluster and `kubectl`.
- Shell access to the node, because `hostPath` needs the directory to exist
  there. Single-node only.

Create the backing directory **on the node**:

```bash
sudo mkdir -p /mnt/d4-manual-pv
sudo chmod 0777 /mnt/d4-manual-pv
```

## Run

All paths are relative to `D4-Storage-/`.

```bash
kubectl apply -f ex02-static-pv-hostpath/namespace.yaml
kubectl apply -f ex02-static-pv-hostpath/pv.yaml
kubectl get pv manual-pv                      # Available, no claim yet

kubectl apply -f ex02-static-pv-hostpath/pvc-and-pod.yaml
kubectl wait --for=condition=Ready pod/manual-writer -n d4-storage --timeout=60s

kubectl get pvc manual-claim -n d4-storage    # Bound to manual-pv
kubectl exec manual-writer -n d4-storage -- cat /data/marker.txt
sudo cat /mnt/d4-manual-pv/marker.txt         # on the node - the same file
```

Then show `Retain` and the `Released` trap:

```bash
kubectl delete pod manual-writer -n d4-storage --now
kubectl delete pvc manual-claim -n d4-storage

kubectl get pv manual-pv                      # Released, NOT deleted
sudo cat /mnt/d4-manual-pv/marker.txt         # data still there

# A fresh PVC will NOT bind to it - the PV still holds a claimRef:
kubectl get pv manual-pv -o jsonpath='{.spec.claimRef}'
```

To make it bindable again, clear the stale reference:

```bash
kubectl patch pv manual-pv -p '{"spec":{"claimRef":null}}'
```

## Clean up

```bash
kubectl delete -f ex02-static-pv-hostpath/pvc-and-pod.yaml --ignore-not-found
kubectl delete -f ex02-static-pv-hostpath/pv.yaml --ignore-not-found
sudo rm -rf /mnt/d4-manual-pv
```

See [OUTPUT.md](OUTPUT.md) for a captured run.
