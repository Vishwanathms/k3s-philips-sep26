# D4 — Storage

Five exercises on Kubernetes persistent storage, from the k3s default
provisioner to a real CSI driver. Every exercise runs in the namespace
`d4-storage` and ships its own `namespace.yaml`, so each one is independently
runnable — apply it, read its `README.md`, run it, clean up.

| # | Exercise | Shows | Extra setup |
|---|----------|-------|-------------|
| 01 | [ex01-local-path-dynamic](ex01-local-path-dynamic/) | Dynamic provisioning, `WaitForFirstConsumer`, `Delete` reclaim | none |
| 02 | [ex02-static-pv-hostpath](ex02-static-pv-hostpath/) | Static provisioning, `Retain`, the `Released` PV trap | a directory on the node |
| 03 | [ex03-nfs-storage](ex03-nfs-storage/) | Network storage, `ReadWriteMany`, two Pods one volume | NFS server (script) |
| 04 | [ex04-csi-nfs-dynamic](ex04-csi-nfs-dynamic/) | A real CSI driver provisioning per-PVC volumes | ex03's NFS export + driver install |
| 05 | [ex05-statefulset-storage](ex05-statefulset-storage/) | `volumeClaimTemplates`, one PVC per replica, stable identity | none |

The arc is deliberate: 01 and 05 need nothing but stock k3s; 02 adds a
hand-made PV; 03 puts that PV on the network; 04 automates 03.

## Prerequisites (all exercises)

- A running k3s cluster and a working `kubectl` (`kubectl get nodes`).
- The bundled `local-path` StorageClass as default (`kubectl get sc`).
- `sudo` on the node for ex02, ex03 and ex04.
- `envsubst` for ex03 and ex04 (`sudo apt-get install -y gettext-base`).

## Site-specific values (ex03 and ex04)

Nothing is hard-coded to this lab's addresses. [`env.sh`](env.sh) auto-detects
the three values ex03 and ex04 need and prints them, so you can check them
before applying anything:

```bash
source env.sh
# NFS_SERVER=...  NODE_SUBNET=...  NFS_EXPORT_DIR=/srv/nfs/k3s-training
```

Override any of them by exporting first — for an NFS server that isn't this
node, or a LAN wider than the assumed /24:

```bash
NFS_SERVER=10.0.0.5 NODE_SUBNET=192.168.230.0/23 source env.sh
```

`ex03/pv-pvc.yaml` and `ex04/storageclass.yaml` hold `${NFS_SERVER}` and
`${NFS_EXPORT_DIR}` placeholders, so they are applied through `envsubst`
rather than directly:

```bash
envsubst < ex03-nfs-storage/pv-pvc.yaml | kubectl apply -f -
```

A plain `kubectl apply -f` on those two files would send the literal string
`${NFS_SERVER}` to the API server. Every other manifest in D4 applies
normally. `setup-nfs-server.sh` sources `env.sh` itself.

## Verified runs

Each exercise has an `OUTPUT.md` with real captured console output from a
single-node k3s `v1.36.4+k3s1` lab, including the failures worth seeing.
