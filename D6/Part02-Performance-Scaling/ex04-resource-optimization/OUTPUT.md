# ex04 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
namespace `day09-scaling`. Result: **PASS** — HPA (CPU) and VPA (memory
only, via `controlledResources`) ran against the **same** Deployment
simultaneously without conflicting, because each was made authoritative
over a different resource.

## Why this needs care in the first place

HPA and VPA **fight each other** if both are configured to react to the
same resource (typically CPU) on the same workload: VPA changes the
container's `requests.cpu`, which changes the *denominator* HPA's
percentage-of-request target is computed against, which changes HPA's
scaling decision, which changes per-Pod load, which VPA then reacts to
again. This is documented, known behavior in the VPA project, not a
hypothetical — the safe pattern is to split responsibility:

- **HPA** scales **replica count** based on **CPU**.
- **VPA** right-sizes **memory** only (`controlledResources: ["memory"]`),
  since memory usage per replica doesn't change just because HPA added or
  removed replicas.

## The combination, deployed together

```console
$ kubectl apply -f ex04-resource-optimization/deployment.yaml
$ kubectl apply -f ex04-resource-optimization/hpa-cpu.yaml
$ kubectl apply -f ex04-resource-optimization/vpa-memory-only.yaml

$ kubectl get hpa php-apache
NAME         REFERENCE               TARGETS       MINPODS   MAXPODS   REPLICAS
php-apache   Deployment/php-apache   cpu: 0%/50%   1         5         1

$ kubectl describe vpa php-apache
Recommendation:
  Container Recommendations:
    Container Name:  php-apache
    Lower Bound:      { Memory: 250Mi }
    Target:           { Memory: 250Mi }
    Upper Bound:      { Memory: 4892275708 }
```

The VPA recommendation contains **only** a `Memory` field — no `Cpu` field
at all, because `controlledResources: ["memory"]` told it not to look at
CPU. Meanwhile the HPA tracks CPU utilization completely independently.
Neither one has any input into the other's decision — there is nothing for
them to fight over.

## The practical takeaway

Before combining HPA and VPA on the same workload, check
`spec.metrics[].resource.name` on the HPA against
`spec.resourcePolicy.containerPolicies[].controlledResources` on the VPA —
they must not overlap. If you want VPA to manage CPU too, don't put an HPA
on CPU for that workload; scale replicas some other way (a schedule, a
custom metric, or manually per `ex01`).
