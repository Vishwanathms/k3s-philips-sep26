# ex02 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
namespace `day09-scaling`. Result: **PASS** — a real HPA scaled a real
CPU-bound workload from 1 → 5 replicas under real load, and back down to 1
once the load stopped, with the exact conservative timing Kubernetes
documents.

```console
$ kubectl apply -f ex02-horizontal-pod-autoscaler/deployment.yaml
deployment.apps/php-apache created
service/php-apache created
$ kubectl apply -f ex02-horizontal-pod-autoscaler/hpa.yaml
horizontalpodautoscaler.autoscaling/php-apache created

$ kubectl get hpa php-apache   # right after creating it
NAME         REFERENCE               TARGETS              REPLICAS
php-apache   Deployment/php-apache   cpu: <unknown>/50%   0
error: metrics not available yet
```

`<unknown>` and "metrics not available yet" are normal for the first ~15–30s
— metrics-server needs at least one scrape before the HPA has anything to
compute against.

```console
$ kubectl get hpa php-apache   # ~45s later
NAME         REFERENCE               TARGETS       REPLICAS
php-apache   Deployment/php-apache   cpu: 0%/50%   1
```

## Scale-up under real load

```console
$ kubectl apply -f ex02-horizontal-pod-autoscaler/load-generator.yaml
pod/load-generator created
```

`load-generator` runs 8 parallel `wget` loops against `php-apache`, whose
`/` endpoint deliberately burns CPU computing `sqrt()` in a tight loop.

| Elapsed | `cpu: current/target` | Replicas |
|---|---|---|
| +10s | `0%/50%` | 1 |
| +20s | `0%/50%` | 1 |
| +30s | `127%/50%` | 1 → 3 (rescale in progress) |
| +40s | `250%/50%` | 3 → 5 |
| +50s | `250%/50%` | 5 |
| +60s–90s | settles `160–209%/50%` | 5 (`maxReplicas` ceiling) |

```console
$ kubectl describe hpa php-apache
Events:
  Normal  SuccessfulRescale  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal  SuccessfulRescale  New size: 5; reason: cpu resource utilization (percentage of request) above target
```

Utilization stays well above `50%` even at 5 replicas (`maxReplicas`) —
8 parallel request loops generate more CPU demand than 5 Pods at the target
can absorb, so the HPA correctly pins at its ceiling rather than
overshooting it.

## Scale-down after the load stops — the conservative part

```console
$ kubectl delete pod load-generator -n day09-scaling
pod "load-generator" deleted
```

| Elapsed since load removed | `cpu` | Replicas |
|---|---|---|
| +30s | `147%/50%` | 5 |
| +60s | `0%/50%` | 5 — **not yet scaled down** |
| +60s → +6m45s | `0%/50%` | still **5** |
| ~+7m45s | `0%/50%` | **1** |

```console
$ kubectl describe hpa php-apache
Conditions:
  AbleToScale   True   ScaleDownStabilized   recent recommendations were higher
                                              than current one, applying the
                                              highest recent recommendation
```

CPU usage dropped to `0%` almost immediately, but the replica count stayed
at `5` for several minutes — the HPA's default **scale-down stabilization
window** (5 minutes) deliberately holds onto the *highest* recent
recommendation before shrinking, specifically to avoid flapping up and down
on a bursty workload. Scaling up reacted in under a minute; scaling down
took roughly six times as long, on purpose. That asymmetry is a real,
default Kubernetes behavior, not a bug in this setup.
