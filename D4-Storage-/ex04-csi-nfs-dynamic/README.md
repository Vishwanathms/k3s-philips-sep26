# ex04 — Dynamic provisioning with the CSI NFS driver

**What it shows:** the same NFS export as ex03, but now a real CSI driver
creates a PV *and its own subdirectory* per PVC, automatically. Two claims,
two isolated volumes — contrast with ex03, where every consumer shared the
single PV an admin made. `reclaimPolicy: Delete` means deleting the PVC
removes the subdirectory too.

## Prerequisites

- A running k3s cluster and `kubectl`.
- `envsubst` (`sudo apt-get install -y gettext-base`).
- **The NFS server from ex03.** If you have not run it yet:

  ```bash
  source env.sh
  bash ex03-nfs-storage/setup-nfs-server.sh
  showmount -e localhost
  ```

  You do not need ex03's PV/PVC/Pods — only the export.
- Internet access on the node: the install script pulls the driver manifests
  from GitHub.

Load the lab's site-specific values (auto-detected, and printed so you can
check them) and install the driver — safe to re-run:

```bash
source env.sh
bash ex04-csi-nfs-dynamic/install-csi-driver.sh
kubectl get csidriver nfs.csi.k8s.io
```

## Run

All paths are relative to `D4-Storage-/`, in the shell where you ran
`source env.sh`.

`storageclass.yaml` carries `${NFS_SERVER}`/`${NFS_EXPORT_DIR}` placeholders,
so it is rendered through `envsubst` rather than applied directly:

```bash
kubectl apply -f ex04-csi-nfs-dynamic/namespace.yaml
envsubst < ex04-csi-nfs-dynamic/storageclass.yaml | kubectl apply -f -

# Check what actually got applied:
kubectl get sc nfs-csi -o jsonpath='{.parameters}{"\n"}'

kubectl apply -f ex04-csi-nfs-dynamic/pvcs-and-pods.yaml
kubectl wait --for=condition=Ready pod/csi-writer-a pod/csi-writer-b -n d4-storage --timeout=90s

# Two claims, two auto-created PVs:
kubectl get pvc csi-claim-a csi-claim-b -n d4-storage
kubectl get pv

# Each Pod sees only its own data - separate subdirectories:
kubectl exec csi-writer-a -n d4-storage -- cat /data/marker.txt
kubectl exec csi-writer-b -n d4-storage -- cat /data/marker.txt

# And on the NFS server, one directory per PV:
sudo ls "$NFS_EXPORT_DIR"
```

Show `reclaimPolicy: Delete`:

```bash
kubectl delete pod csi-writer-a -n d4-storage --now
kubectl delete pvc csi-claim-a -n d4-storage
kubectl get pv                                  # claim-a's PV is gone
sudo ls "$NFS_EXPORT_DIR"                   # so is its subdirectory
```

## Clean up

```bash
kubectl delete -f ex04-csi-nfs-dynamic/pvcs-and-pods.yaml --ignore-not-found
envsubst < ex04-csi-nfs-dynamic/storageclass.yaml | kubectl delete --ignore-not-found -f -
```

Delete the Pods before the PVCs, or the PVCs will sit in `Terminating` until
their consumers are gone.

See [OUTPUT.md](OUTPUT.md) for a captured run.
