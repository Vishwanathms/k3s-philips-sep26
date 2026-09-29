# ex03 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
namespace `day09-scaling`. Result: **PASS** — a real, installed VPA
(`kubernetes/autoscaler`'s official Helm chart, v1.7.1 — not part of k3s by
default) recommended real numbers for a deliberately under-provisioned
container, then actually applied them by recreating the Pods.

## Installing VPA (once, for this whole day)

```console
$ git clone --filter=blob:none --sparse https://github.com/kubernetes/autoscaler.git
$ git sparse-checkout set vertical-pod-autoscaler
$ helm install vpa vertical-pod-autoscaler/charts/vertical-pod-autoscaler -n kube-system
NOTES:
Vertical Pod Autoscaler has been installed!
Components deployed:
   ✓ admission-controller
   ✓ recommender
   ✓ updater

$ kubectl -n kube-system get pods -l app.kubernetes.io/name=vertical-pod-autoscaler
vpa-...-admission-controller-...   1/1   Running   (x2)
vpa-...-recommender-...            1/1   Running   (x2)
vpa-...-updater-...                1/1   Running   (x2)

$ kubectl get crd | grep autoscaling.k8s.io
verticalpodautoscalercheckpoints.autoscaling.k8s.io
verticalpodautoscalers.autoscaling.k8s.io
```

Unlike `local-path-provisioner`/`csi-driver-nfs` (already on this cluster
from earlier days), VPA is not part of k3s at all — it's the same upstream
`kubernetes/autoscaler` project HPA (`ex02`) comes from, installed the same
way any cluster would.

## The workload: deliberately under-provisioned

```console
$ kubectl apply -f ex03-vertical-pod-autoscaler/deployment.yaml
$ kubectl get pod -l app=rightsize-me -o jsonpath='{.items[0].spec.containers[0].resources}'
{"limits":{"cpu":"500m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"16Mi"}}

$ kubectl top pod -l app=rightsize-me
NAME                            CPU(cores)   MEMORY(bytes)
rightsize-me-6b5bf86db8-l9b5q   500m         2Mi
```

`requests.cpu: 10m` but real usage is already pinned at the **500m limit**
— the container is being CPU-throttled the entire time, and the scheduler
thinks it only needs 1/50th of that.

## `updateMode: Off` — recommend only

```console
$ kubectl apply -f ex03-vertical-pod-autoscaler/vpa-off.yaml
$ kubectl describe vpa rightsize-me   # ~90s later
Recommendation:
  Container Recommendations:
    Container Name:  hasher
    Lower Bound:    { Cpu: 102m,  Memory: 250Mi }
    Target:         { Cpu: 587m,  Memory: 250Mi }
    Upper Bound:    { Cpu: 818599m, Memory: 16037306451 }
```

`Target: 587m` vs. the actual `requests.cpu: 10m` — a real, measured ~59×
under-request. Note the enormous `Upper Bound` (819 CPUs!) — with only ~90
seconds of history, the recommender's statistical confidence interval is
still extremely wide; it narrows over hours, not seconds. `Off` mode never
touches the running Pod — this recommendation was pure observation.

## `updateMode: Recreate` — a real safety guard, hit first

```console
$ kubectl apply -f ex03-vertical-pod-autoscaler/vpa-auto.yaml
Warning: UpdateMode "Auto" is deprecated ... Use explicit update modes like
  "Recreate", "Initial", or "InPlaceOrRecreate" instead.
```

(fixed to `updateMode: Recreate` — the current, non-deprecated name for the
same behavior.) Nothing happened for minutes. The updater's own logs
explained why:

```console
$ kubectl -n kube-system logs -l app.kubernetes.io/component=updater --tail=5
"Too few replicas" kind="ReplicaSet" object="day09-scaling/rightsize-me-...”
  livePods=1 requiredPods=2 globalMinReplicas=2
```

The updater **refuses to evict** a Pod if doing so would drop a workload
below its configured minimum replica floor (default `2`) — with only 1
replica, evicting it means 0 running Pods, so it safely does nothing
instead. This is a real, deliberate availability guard, not a stuck lab.

```console
$ kubectl scale deployment/rightsize-me -n day09-scaling --replicas=2
$ kubectl get pods -l app=rightsize-me   # ~30s later
rightsize-me-...-l9b5q   Terminating
rightsize-me-...-vlqz5   Running   (new)
rightsize-me-...-xsdbs   Running   (new)
```

With 2 replicas, the updater evicted both original Pods (one at a time) and
let the Deployment recreate them — this time through the VPA admission
webhook.

## The resized Pods

```console
$ kubectl get pods -l app=rightsize-me -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.containers[0].resources}{"\n"}{end}'
rightsize-me-...-vlqz5: {"limits":{"cpu":"29350m","memory":"2000Mi"},"requests":{"cpu":"587m","memory":"250Mi"}}
rightsize-me-...-xsdbs: {"limits":{"cpu":"29350m","memory":"2000Mi"},"requests":{"cpu":"587m","memory":"250Mi"}}

$ kubectl describe pod -l app=rightsize-me | grep vpaUpdates
vpaUpdates: Pod resources updated by rightsize-me: container 0: cpu request, memory request, cpu limit, memory limit
```

`requests.cpu` moved `10m → 587m` — **exactly** the recommender's `Target`.
Note what happened to the **limit**: `500m → 29350m`, and `128Mi → 2000Mi`.
Neither matches the recommendation directly — VPA preserved the *original
limit-to-request ratio* (`500m/10m = 50×`, `128Mi/16Mi = 8×`) and scaled the
new limit by that same factor (`587m × 50 = 29350m`; `250Mi × 8 = 2000Mi`).
This is real, current VPA behavior when no explicit `LimitRange`/max is
configured — worth checking against your own `resources.limits` policy (Day
07's `LimitRange`, `ex05`) before turning on `Recreate` in a shared
namespace, since an aggressive original ratio gets amplified, not capped.
