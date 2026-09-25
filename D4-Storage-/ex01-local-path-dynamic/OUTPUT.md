# ex01 — verified run

Captured **2026-09-12** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
namespace `d4-storage`. Result: **PASS** — the PVC stayed `Pending` until
a Pod consumed it, local-path-provisioner then created a real PV backed by a
directory on the node, and the data survived deleting and recreating the Pod.

```console
$ kubectl apply -f ex01-local-path-dynamic/pvc.yaml
persistentvolumeclaim/data-claim created

$ kubectl get pvc data-claim -n d4-storage
NAME         STATUS    VOLUME   STORAGECLASS   AGE
data-claim   Pending            local-path     1s
```

`Pending` here is **expected**, not a failure — `local-path`'s
`volumeBindingMode: WaitForFirstConsumer` delays provisioning until a Pod
that references the PVC is actually scheduled, so the volume is created on
the same node the Pod lands on.

```console
$ kubectl apply -f ex01-local-path-dynamic/pod.yaml
pod/writer created
$ kubectl wait --for=condition=Ready pod/writer -n d4-storage --timeout=60s
pod/writer condition met

$ kubectl get pvc data-claim -n d4-storage
NAME         STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
data-claim   Bound    pvc-2f03cfda-0a27-4395-8a2d-d395f2ab5516   100Mi      RWO            local-path

$ kubectl get pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM
pvc-2f03cfda-0a27-4395-8a2d-d395f2ab5516   100Mi      RWO            Delete           Bound    d4-storage/data-claim
```

Where local-path actually put it on the node:

```console
$ sudo ls -la /var/lib/rancher/k3s/storage/
drwxrwxrwx 2 root root 4096 Sep 12 21:29 pvc-2f03cfda-0a27-4395-8a2d-d395f2ab5516_d4-storage_data-claim
```

## Persistence across a Pod restart

```console
$ kubectl exec writer -n d4-storage -- cat /data/log
Sat Sep 12 15:59:47 UTC 2026
Sat Sep 12 15:59:49 UTC 2026
Sat Sep 12 15:59:51 UTC 2026
Sat Sep 12 15:59:53 UTC 2026

$ kubectl delete pod writer -n d4-storage --now
pod "writer" deleted
$ kubectl apply -f ex01-local-path-dynamic/pod.yaml
pod/writer created
$ kubectl wait --for=condition=Ready pod/writer -n d4-storage --timeout=60s
pod/writer condition met

$ kubectl exec writer -n d4-storage -- cat /data/log
Sat Sep 12 15:59:47 UTC 2026     # <- from the OLD pod
Sat Sep 12 15:59:49 UTC 2026
Sat Sep 12 15:59:51 UTC 2026
Sat Sep 12 15:59:53 UTC 2026
Sat Sep 12 15:59:55 UTC 2026
Sat Sep 12 15:59:57 UTC 2026
Sat Sep 12 15:59:59 UTC 2026
Sat Sep 12 16:00:01 UTC 2026
Sat Sep 12 16:00:06 UTC 2026     # <- from the NEW pod, same file
Sat Sep 12 16:00:08 UTC 2026
```

The Pod was destroyed and recreated; the PersistentVolume — and the file on
it — was not.
