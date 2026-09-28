# ex01 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
namespace `d5-health`. Result: **PASS** — the container ran healthy for
30s, the liveness probe caught it going unhealthy, and kubelet restarted it.

```console
$ kubectl apply -f ex01-liveness-probe/pod.yaml
pod/liveness-demo created
$ kubectl wait --for=condition=Ready pod/liveness-demo -n d5-health --timeout=30s
pod/liveness-demo condition met

$ kubectl get pod liveness-demo -n d5-health
NAME            READY   STATUS    RESTARTS   AGE
liveness-demo   1/1     Running   0          3s
```

After ~35s (30s healthy + probe interval), the health marker file is gone and
the probe starts failing:

```console
$ kubectl get pod liveness-demo -n d5-health
NAME            READY   STATUS    RESTARTS      AGE
liveness-demo   1/1     Running   1 (14s ago)   80s

$ kubectl describe pod liveness-demo -n d5-health
Events:
  Type     Reason     Age   From      Message
  ----     ------     ----  ----      -------
  Warning  Unhealthy  44s   kubelet   Liveness probe failed: cat: can't open '/tmp/healthy': No such file or directory
  Normal   Killing    44s   kubelet   Container app failed liveness probe, will be restarted
  Normal   Pulled     14s (x2 over 78s)  kubelet   Container image "busybox:1.36" already present on machine and can be accessed by the pod
  Normal   Created    14s (x2 over 78s)  kubelet   Container created
  Normal   Started    13s (x2 over 77s)  kubelet   Container started
```

`(x2 over 78s)` on `Pulled`/`Created`/`Started` is the tell: the container
was created and started **twice** — once at Pod creation, once after the
liveness-triggered restart. `RESTARTS` went from `0` to `1`, and the reason
is right there in the events — not a crash, not an OOM, a **liveness probe
failure** that kubelet chose to react to by killing and recreating the
container.

Note the delay between the first `Unhealthy`/`Killing` event (44s ago) and
the container actually restarting (14s ago, `Started` `13s ago`) — killing a
container and starting its replacement isn't instantaneous.
