# ex03 — verified run

Captured **2026-09-12** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
namespace `d4-storage`. Result: **PASS** — two independent Pods mounted
the same NFS-backed PV simultaneously and both read and wrote to it.

```console
$ envsubst < ex03-nfs-storage/pv-pvc.yaml | kubectl apply -f -
persistentvolume/nfs-pv created
persistentvolumeclaim/nfs-claim created

$ kubectl get pvc nfs-claim -n d4-storage
NAME        STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
nfs-claim   Bound    nfs-pv   500Mi      RWX            nfs-manual

$ kubectl get pv nfs-pv
NAME     CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM
nfs-pv   500Mi      RWX            Retain           Bound    d4-storage/nfs-claim
```

Unlike ex01/ex02 (`RWO`, `local-path`/`hostPath`), this PVC bound
**immediately** — no `WaitForFirstConsumer` delay, because it isn't going
through a dynamic provisioner at all; it's a direct static match on
`storageClassName`.

```console
$ kubectl apply -f ex03-nfs-storage/pods.yaml
pod/nfs-writer created
pod/nfs-reader created

$ kubectl exec nfs-reader -n d4-storage -- cat /data/shared.txt
from-nfs-writer
```

`nfs-reader` never talked to `nfs-writer` — both mounted the same NFS export
independently, and the second Pod saw the first Pod's write immediately.

```console
$ kubectl exec nfs-reader -n d4-storage -- sh -c 'echo from-nfs-reader >> /data/shared.txt'
$ kubectl exec nfs-writer -n d4-storage -- cat /data/shared.txt
from-nfs-writer
from-nfs-reader
```

Writes go both directions — this is genuine `ReadWriteMany`, which
`local-path` (ex01) cannot offer. Confirmed on the actual NFS export on the
node:

```console
$ cat /srv/nfs/k3s-training/shared.txt
from-nfs-writer
from-nfs-reader
```

## How the NFS server was set up (once, for this whole day)

```console
$ bash ex03-nfs-storage/setup-nfs-server.sh
Installing nfs-kernel-server (no-op if already installed)...
Creating and permissioning /srv/nfs/k3s-training...
Writing /etc/exports...
Reloading exports and (re)starting the server...

Done. Current exports:
/srv/nfs/k3s-training
		127.0.0.1(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,no_root_squash,no_all_squash)
/srv/nfs/k3s-training
		10.42.0.0/16(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,no_root_squash,no_all_squash)
/srv/nfs/k3s-training
		192.168.230.0/23(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,no_root_squash,no_all_squash)

Server status:
active
```

**A real quirk found while first wiring this up (before the script existed):**
the export originally allowed only `10.42.0.0/16` (the Pod CIDR) and
`127.0.0.1`, and mounting failed with `mount.nfs: access denied by server`.
The Kubernetes in-tree NFS volume plugin has the **kubelet** (on the node's
own IP, `192.168.230.103`) perform the mount and bind it into the Pod — the
NFS client connection comes from the **node's** IP, not a Pod IP. The export
had to also allow the node's own subnet (`192.168.230.0/23`) before it
worked — `setup-nfs-server.sh` bakes in that fix, and its `NODE_SUBNET`
variable is the one thing to edit if you point this at a different network.

Confirmed a Pod can still mount and write through it after the script runs:

```console
$ kubectl run nfs-script-check --image=busybox:1.36 --restart=Never --overrides='...nfs volume, server 192.168.230.103, path /srv/nfs/k3s-training...' \
    -- sh -c "echo script-created-this-share > /mnt/nfs/check.txt && cat /mnt/nfs/check.txt"
script-created-this-share

$ cat /srv/nfs/k3s-training/check.txt   # on the node
script-created-this-share
```
