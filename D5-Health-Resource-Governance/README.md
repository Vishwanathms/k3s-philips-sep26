# D5 — Health Management & Resource Governance

Builds directly on:

- **Day 01–06:** workloads, Services, Secrets, RBAC, networking internals,
  Ingress/traffic management, and storage.

This module is about keeping workloads honest: how Kubernetes decides a
container is alive, ready, or still starting (liveness/readiness/startup
probes), and how it decides who gets how much CPU/memory, what happens when
they ask for too much or use too much, and who gets sacrificed first when
the node runs low (requests, limits, ResourceQuota, LimitRange, QoS
classes).

| Material | Purpose |
|---|---|
| [LAB-MANUAL.md](LAB-MANUAL.md) | The six labs, start to finish, with checkpoints |
| [Student-Guide-Kubernetes-Liveness-Probe-Configuration.docx](Student-Guide-Kubernetes-Liveness-Probe-Configuration.docx) | Student handout on configuring liveness probes |
| [Student-Reference-StatefulSet-Headless-Service-Redis.docx](Student-Reference-StatefulSet-Headless-Service-Redis.docx) | Student reference: StatefulSet + headless Service with redis |

## Hands-on labs

| # | Lab | Proves | Verified run |
|---|-----|--------|--------------|
| 1 | [ex01-liveness-probe](ex01-liveness-probe/) | a failed liveness probe gets the container **killed and restarted** | [OUTPUT.md](ex01-liveness-probe/OUTPUT.md) |
| 2 | [ex02-readiness-probe](ex02-readiness-probe/) | a failed readiness probe pulls the Pod out of Service endpoints — **no restart**, traffic just stops routing there | [OUTPUT.md](ex02-readiness-probe/OUTPUT.md) |
| 3 | [ex03-startup-probe](ex03-startup-probe/) | the same slow-starting container crash-loops forever without a startup probe, and starts cleanly with one | [OUTPUT.md](ex03-startup-probe/OUTPUT.md) |
| 4 | [ex04-requests-limits](ex04-requests-limits/) | requests drive scheduling (`Insufficient cpu`); CPU limits **throttle** (cgroup `cpu.stat`); memory limits **kill** (`OOMKilled`, exit 137) | [OUTPUT.md](ex04-requests-limits/OUTPUT.md) |
| 5 | [ex05-resourcequota-limitrange](ex05-resourcequota-limitrange/) | `LimitRange` auto-fills and bounds container resources; `ResourceQuota` hard-caps the whole namespace, rejecting at creation time | [OUTPUT.md](ex05-resourcequota-limitrange/OUTPUT.md) |
| 6 | [ex06-qos-classes](ex06-qos-classes/) | Guaranteed/Burstable/BestEffort, and the real kernel `oom_score_adj` behind "BestEffort dies first" | [OUTPUT.md](ex06-qos-classes/OUTPUT.md) |

Start with [LAB-MANUAL.md](LAB-MANUAL.md). All six were run verbatim against
this cluster on **2026-09-13** — every lab's own `OUTPUT.md` (linked above)
has the full captured transcript, real error messages and kernel-level
evidence included.

```bash
kubectl delete namespace d5-health   # fast cleanup for lab objects
```

## Capstone stage 01

After the labs above, students start the course capstone: they build and
push the images for a 3-tier app (nginx → python → redis), deploy it, and
apply today's probes, requests/limits, LimitRange, ResourceQuota and QoS to
it. Manual: [CAPSTONE/Stage01-build-deploy-health/LAB-MANUAL.md](../CAPSTONE/Stage01-build-deploy-health/LAB-MANUAL.md).
The app is kept and extended every day until Day 14 (see [CAPSTONE/README.md](../CAPSTONE/README.md)).

## Single-node scope

Every lab here is fully real on one node — probes, requests/limits,
ResourceQuota/LimitRange, and QoS classes are per-Pod/per-namespace
mechanics that don't need a second node to demonstrate honestly. The one
thing genuinely different on a multi-node cluster is **node-level eviction
under real memory pressure** (`ex06` shows the `oom_score_adj` mechanism
behind it, but this lab deliberately does not starve the node itself to
trigger it for real — that would affect every other lab/service sharing
this VM).

## Prerequisites

```bash
kubectl get nodes                           # Ready
kubectl top node                            # metrics-server available (used in ex04)
kubectl describe node | grep -A6 Allocatable   # know your real CPU/memory ceiling
```
