# ex05 — verified run

Captured **2026-09-12** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
namespace `d4-storage`. Result: **PASS** — each replica got its own PVC
via `volumeClaimTemplates`, and deleting one Pod reattached the **same**
PVC to its replacement rather than starting fresh.

```console
$ kubectl apply -f ex05-statefulset-storage/statefulset.yaml
service/counter created
statefulset.apps/counter created

$ kubectl rollout status statefulset/counter -n d4-storage --timeout=90s
Waiting for 2 pods to be ready...
Waiting for 1 pods to be ready...
partitioned roll out complete: 2 new pods have been updated...

$ kubectl get pods -n d4-storage -l app=counter -o wide
NAME        READY   STATUS    AGE
counter-0   1/1     Running   13s     # created first...
counter-1   1/1     Running   6s      # ...then this one - ordered, not parallel

$ kubectl get pvc -n d4-storage
NAME             STATUS   VOLUME                                     STORAGECLASS
data-counter-0   Bound    pvc-bb8160f1-a3df-4843-a1ca-e86dcb914aff   local-path
data-counter-1   Bound    pvc-d7e530da-af2b-4d81-8a18-805131220432   local-path
```

One PVC **per replica**, auto-named `<template-name>-<pod-name>` — a
Deployment with the same `volumeClaimTemplates` idea would need a manual
PVC-per-replica scheme; a StatefulSet does it natively.

```console
$ kubectl exec counter-0 -n d4-storage -- head -1 /data/identity.log
I am counter-0, first boot at Sat Sep 12 16:05:13 UTC 2026
$ kubectl exec counter-1 -n d4-storage -- head -1 /data/identity.log
I am counter-1, first boot at Sat Sep 12 16:05:19 UTC 2026
```

Each replica only ever sees its own log — proving the PVCs are isolated per
Pod, not shared.

## Deleting a Pod reattaches its own PVC, not a fresh one

```console
$ kubectl delete pod counter-0 -n d4-storage --now
pod "counter-0" deleted
# StatefulSet recreates it with the SAME name: counter-0

$ kubectl exec counter-0 -n d4-storage -- cat /data/identity.log
I am counter-0, first boot at Sat Sep 12 16:05:13 UTC 2026   # <- original boot marker, preserved
Sat Sep 12 16:05:13 UTC 2026
Sat Sep 12 16:05:18 UTC 2026
Sat Sep 12 16:05:23 UTC 2026
Sat Sep 12 16:05:28 UTC 2026
I am counter-0, first boot at Sat Sep 12 16:05:34 UTC 2026   # <- second boot marker, from the restart
Sat Sep 12 16:05:34 UTC 2026
Sat Sep 12 16:05:39 UTC 2026
Sat Sep 12 16:05:44 UTC 2026
Sat Sep 12 16:05:49 UTC 2026
```

Two "first boot" lines in one file, with the old timestamps still between
them: the container restarted clean, but `data-counter-0` — and everything
already written to it — was reattached rather than recreated. That's the
stable-identity guarantee a StatefulSet gives that a Deployment does not.
