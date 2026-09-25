# ex04 — verified run

Captured **2026-09-12** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
namespace `d4-storage`. Result: **PASS** — a real CSI driver dynamically
provisioned two independent, isolated volumes on the same NFS export ex03
used statically, and `Delete` reclaim cleaned one up automatically while the
other stayed untouched.

```console
$ bash ex04-csi-nfs-dynamic/install-csi-driver.sh
Installing NFS CSI driver, version: v4.13.4 ...
serviceaccount/csi-nfs-controller-sa created
csidriver.storage.k8s.io/nfs.csi.k8s.io created
deployment.apps/csi-nfs-controller created
daemonset.apps/csi-nfs-node created
NFS CSI driver installed successfully.

$ kubectl get csidriver nfs.csi.k8s.io
NAME             ATTACHREQUIRED   MODES
nfs.csi.k8s.io   false            Persistent
```

`kubectl get csidrivers` returned **nothing** before this — `local-path`
(ex01) is not a CSI driver at all; it predates the CSI spec and is
implemented as an external provisioner watching PVCs directly.

```console
$ envsubst < ex04-csi-nfs-dynamic/storageclass.yaml | kubectl apply -f -
storageclass.storage.k8s.io/nfs-csi created
$ kubectl apply -f ex04-csi-nfs-dynamic/pvcs-and-pods.yaml
persistentvolumeclaim/csi-claim-a created
persistentvolumeclaim/csi-claim-b created
pod/csi-writer-a created
pod/csi-writer-b created

$ kubectl get pvc csi-claim-a csi-claim-b -n d4-storage
NAME          STATUS   VOLUME                                     STORAGECLASS
csi-claim-a   Bound    pvc-62fd3e43-e475-4e0d-b245-83350280c35e   nfs-csi
csi-claim-b   Bound    pvc-3728c26e-f409-4892-8af3-9e1d37da0cfd   nfs-csi
```

Each PVC got its **own** PV automatically — nobody hand-wrote either one.

```console
$ kubectl exec csi-writer-a -n d4-storage -- cat /data/marker.txt
from-claim-a
$ kubectl exec csi-writer-b -n d4-storage -- cat /data/marker.txt
from-claim-b

$ ls /srv/nfs/k3s-training/
pvc-3728c26e-f409-4892-8af3-9e1d37da0cfd
pvc-62fd3e43-e475-4e0d-b245-83350280c35e

$ kubectl exec csi-writer-a -n d4-storage -- ls /data/
marker.txt
```

The CSI driver created one subdirectory **per PVC** on the export and mounts
only that subdirectory into each Pod — `csi-writer-a` cannot see
`csi-writer-b`'s files even though both ultimately live under
`/srv/nfs/k3s-training` on the same NFS server. That's the isolation a real
provisioner adds on top of ex03's one-PV-shared-by-everyone static setup.

## `Delete` reclaim, fully automated

```console
$ kubectl delete pod csi-writer-a -n d4-storage --now
$ kubectl delete pvc csi-claim-a -n d4-storage

$ kubectl get pv | grep nfs-csi
pvc-3728c26e-f409-4892-8af3-9e1d37da0cfd   ...   Bound   d4-storage/csi-claim-b   nfs-csi   # claim-a's PV: gone

$ ls /srv/nfs/k3s-training/
pvc-3728c26e-f409-4892-8af3-9e1d37da0cfd    # claim-a's subdirectory: gone too
```

Compare with ex02/ex03: there, `Retain` left a `Released` PV and its data
sitting around needing a human to clean up or rebind. Here, `Delete` removed
the PV object **and** asked the driver to delete the backing subdirectory —
no leftovers, no manual step, and no chance to recover the data if that was
a mistake.
