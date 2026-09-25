# ex03 — Static PV backed by a real NFS export (ReadWriteMany)

**What it shows:** the same static provisioning as ex02, but on network
storage, so `accessModes` can be `ReadWriteMany` — two Pods mount the one
PVC at the same time and see each other's writes. `hostPath`/`local-path`
cannot do that.

## Prerequisites

- A running k3s cluster and `kubectl`.
- `sudo` on the node where the NFS server will run (this lab runs it on the
  k3s node itself).
- `envsubst` (`sudo apt-get install -y gettext-base`).

Load the lab's site-specific values — they are auto-detected from this node,
and printed so you can check them:

```bash
source env.sh
```

Then set up the NFS server and export:

```bash
bash ex03-nfs-storage/setup-nfs-server.sh
showmount -e localhost        # should list $NFS_EXPORT_DIR
```

The script exports to the Pod CIDR, `$NODE_SUBNET` and `127.0.0.1`. The node
subnet is **required**: the in-tree NFS volume plugin mounts from the
kubelet's IP, not a Pod IP. If auto-detection guessed wrong (a /23 LAN, or an
NFS server that isn't this node), override before sourcing:

```bash
NFS_SERVER=10.0.0.5 NODE_SUBNET=192.168.230.0/23 source env.sh
```

## Run

All paths are relative to `D4-Storage-/`, in the shell where you ran
`source env.sh`.

`pv-pvc.yaml` carries `${NFS_SERVER}`/`${NFS_EXPORT_DIR}` placeholders, so it
is rendered through `envsubst` rather than applied directly:

```bash
kubectl apply -f ex03-nfs-storage/namespace.yaml
envsubst < ex03-nfs-storage/pv-pvc.yaml | kubectl apply -f -

# Check what actually got applied:
kubectl get pv nfs-pv -o jsonpath='{.spec.nfs.server}{"\n"}'

kubectl get pvc nfs-claim -n d4-storage        # Bound immediately - no WaitForFirstConsumer
kubectl get pv nfs-pv

kubectl apply -f ex03-nfs-storage/pods.yaml
kubectl wait --for=condition=Ready pod/nfs-writer pod/nfs-reader -n d4-storage --timeout=90s

# The reader sees what the writer wrote - one volume, two Pods:
kubectl exec nfs-reader -n d4-storage -- cat /data/shared.txt

# And it works both ways:
kubectl exec nfs-reader -n d4-storage -- sh -c 'echo from-nfs-reader >> /data/shared.txt'
kubectl exec nfs-writer -n d4-storage -- cat /data/shared.txt
sudo cat "$NFS_EXPORT_DIR"/shared.txt      # on the NFS server
```

If a Pod is stuck in `ContainerCreating`, read the events —
`mount.nfs: access denied by server` means the export does not cover the
node's IP:

```bash
kubectl describe pod nfs-writer -n d4-storage | tail -20
```

## Clean up

```bash
kubectl delete -f ex03-nfs-storage/pods.yaml --ignore-not-found
envsubst < ex03-nfs-storage/pv-pvc.yaml | kubectl delete --ignore-not-found -f -
```

The PV is `Retain`, so `$NFS_EXPORT_DIR` keeps its files. Leave the NFS
server running — **ex04 reuses this same export.**

See [OUTPUT.md](OUTPUT.md) for a captured run.
