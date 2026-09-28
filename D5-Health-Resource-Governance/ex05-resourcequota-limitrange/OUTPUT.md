# ex05 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
namespace `d5-health`. Result: **PASS** — a `LimitRange` auto-filled
missing resource fields and rejected out-of-bounds ones; a `ResourceQuota`
rejected a Pod the moment the namespace's pod count would exceed 3.

```console
$ kubectl apply -f ex05-resourcequota-limitrange/resourcequota.yaml
resourcequota/team-quota created
$ kubectl apply -f ex05-resourcequota-limitrange/limitrange.yaml
limitrange/team-limits created
```

## LimitRange: defaults for containers that don't ask

```console
$ kubectl run bare-pod --image=busybox:1.36 --restart=Never -- sleep 3600
pod/bare-pod created

$ kubectl get pod bare-pod -o jsonpath='{.spec.containers[0].resources}'
{
    "limits":   {"cpu": "100m", "memory": "64Mi"},
    "requests": {"cpu": "50m",  "memory": "32Mi"}
}
```

The manifest specified **no** `resources:` block at all — the API server
stamped in the `LimitRange`'s `default`/`defaultRequest` values automatically
on admission, before the Pod was even created.

## LimitRange: rejecting out-of-bounds requests

```console
$ kubectl run too-small --image=busybox:1.36 --restart=Never --overrides='...resources: {requests: {cpu: 1m, memory: 4Mi}}...'
Error from server (Forbidden): pods "too-small" is forbidden:
  [minimum cpu usage per Container is 10m, but request is 1m,
   minimum memory usage per Container is 8Mi, but request is 4Mi]

$ kubectl run too-big --image=busybox:1.36 --restart=Never --overrides='...resources: {requests: {memory: 512Mi}, limits: {memory: 1Gi}}...'
Error from server (Forbidden): pods "too-big" is forbidden:
  maximum memory usage per Container is 256Mi, but limit is 1Gi
```

Both rejected **at creation** — no Pod object is ever created, nothing to
clean up, nothing left `Pending`.

## ResourceQuota: a hard ceiling on the whole namespace

```console
$ kubectl run bare-pod-2 --image=busybox:1.36 --restart=Never -- sleep 3600
$ kubectl run bare-pod-3 --image=busybox:1.36 --restart=Never -- sleep 3600

$ kubectl describe resourcequota team-quota
Resource         Used   Hard
--------         ----   ----
limits.cpu       300m   1
limits.memory    192Mi  512Mi
pods             3      3        # <- at the cap
requests.cpu     150m   500m
requests.memory  96Mi   256Mi

$ kubectl run bare-pod-4 --image=busybox:1.36 --restart=Never -- sleep 3600
Error from server (Forbidden): pods "bare-pod-4" is forbidden:
  exceeded quota: team-quota, requested: pods=1, used: pods=3, limited: pods=3
```

Three Pods (each carrying the LimitRange's default 50m/32Mi request, 100m/64Mi
limit) already add up to exactly `150m`/`96Mi` requested and `300m`/`192Mi`
limited — the 4th Pod is rejected purely on the `pods: "3"` cap, before CPU
or memory even come into it. `ResourceQuota` and `LimitRange` compose: the
quota counts whatever the LimitRange already filled in.
