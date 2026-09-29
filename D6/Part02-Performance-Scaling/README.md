# Day 09 — Performance & Scaling

Builds directly on:

- **Day 01–08:** workloads, Services, Secrets, RBAC, networking, Ingress,
  storage, resource governance, and cluster maintenance — everything a
  scaled-up or right-sized workload still depends on.

This module is about workloads under changing load: scaling replicas by
hand, letting an HPA scale them automatically off real CPU metrics, letting
a VPA right-size a single Pod's requests/limits off real usage history, and
planning capacity from this node's actual numbers rather than assumptions.

| Material | Purpose |
|---|---|
| [slides/PPT_CONTENT.md](slides/PPT_CONTENT.md) | Detailed slide-by-slide teaching content, presenter cues, and sources |
| [slides/Day-09-Performance-Scaling.pptx](slides/Day-09-Performance-Scaling.pptx) | Presentation-ready PowerPoint deck |

## Hands-on labs

| # | Lab | Proves | Verified run |
|---|-----|--------|--------------|
| 1 | [ex01-scaling-applications](ex01-scaling-applications/) | manual scaling, both imperative (`kubectl scale`) and declarative (`replicas:`) | [OUTPUT.md](ex01-scaling-applications/OUTPUT.md) |
| 2 | [ex02-horizontal-pod-autoscaler](ex02-horizontal-pod-autoscaler/) | a real HPA scaling 1→5 replicas under real CPU load, and back down to 1 with the real ~5-minute stabilization delay | [OUTPUT.md](ex02-horizontal-pod-autoscaler/OUTPUT.md) |
| 3 | [ex03-vertical-pod-autoscaler](ex03-vertical-pod-autoscaler/) | a real, installed VPA recommending and then applying new requests/limits on a live Pod — including its replica-floor safety guard | [OUTPUT.md](ex03-vertical-pod-autoscaler/OUTPUT.md) |
| 4 | [ex04-resource-optimization](ex04-resource-optimization/) | HPA (CPU) and VPA (memory-only) running on the same Deployment without fighting each other | [OUTPUT.md](ex04-resource-optimization/OUTPUT.md) |
| 5 | [ex05-capacity-planning](ex05-capacity-planning/) | a capacity prediction computed from this node's real numbers, confirmed exactly against the real scheduler | [OUTPUT.md](ex05-capacity-planning/OUTPUT.md) |

Also: [design-cluster-autoscaler-concepts.md](design-cluster-autoscaler-concepts.md)
— how Cluster Autoscaler works and why this single fixed node can't
demonstrate it live (the user's own topic list names it "Concepts" for
exactly that reason).

Start with [LAB-MANUAL.md](LAB-MANUAL.md). All five hands-on labs were run
for real against this cluster on **2026-09-13** — every lab's own
`OUTPUT.md` has the full captured transcript.

```bash
kubectl delete namespace day09-scaling   # fast cleanup for lab objects
```

## What this day needed that earlier days didn't

**A real Vertical Pod Autoscaler was installed** — VPA is not part of k3s
by default (unlike `local-path-provisioner`), so it was installed for real
from the upstream `kubernetes/autoscaler` project's own Helm chart, the same
way `ex04`'s NFS CSI driver was installed in Day 06:

```bash
git clone --filter=blob:none --sparse https://github.com/kubernetes/autoscaler.git
cd autoscaler && git sparse-checkout set vertical-pod-autoscaler
helm install vpa vertical-pod-autoscaler/charts/vertical-pod-autoscaler -n kube-system
```

It's left running in `kube-system` for future days, the same way the NFS
server and CSI driver were left running after Day 06.

## Capstone stage 07

After the labs above, students autoscale the course capstone's API tier:
an `autoscaling/v2` HPA (2–6 replicas, `ContainerResource` CPU because of
the Linkerd sidecar), real load through the Ingress, a quota sized for the
maximum, and a Linkerd before/after comparison of what scaling bought the
users. VPA runs in recommend-only mode for web and redis. Manual:
[CAPSTONE/Stage07-HPA-Scaling/LAB-MANUAL.md](../CAPSTONE/Stage07-HPA-Scaling/LAB-MANUAL.md).

## Prerequisites

```bash
kubectl top node                       # metrics-server available (required for HPA and VPA)
kubectl get crd | grep autoscaling.k8s.io   # VerticalPodAutoscaler CRDs installed
```
