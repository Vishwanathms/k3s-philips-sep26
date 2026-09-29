# Design exercise — Cluster Autoscaler concepts

**Content-only, no cluster changes.** The user's own topic list names this
"Cluster Autoscaler **Concepts**" — and for good reason: Cluster Autoscaler
(CA) adds and removes **nodes** by calling a cloud provider's (or
on-prem provisioner's) API. This course has exactly one node, provisioned
by hand, on a VM with no provisioning API behind it — there is no node pool
for CA to scale, so nothing about it can be demonstrated live here, the
same honest limit this course applied to Cluster Autoscaler concepts.

## How Cluster Autoscaler actually decides

CA is a **separate controller**, not a Kubernetes core feature (unlike HPA)
and not the same project component as VPA, though it lives in the same
`kubernetes/autoscaler` repo `ex02`/`ex03` installed HPA's spec from and
VPA's Helm chart from.

```text
Pod stuck Pending, unschedulable
        |
        v
CA checks: would a NEW node (from a configured node group/pool)
           let this Pod schedule?
        |
        v
   Yes -> call the cloud provider's API to add a node, wait for it
          to join, Pod schedules normally
   No  -> Pod stays Pending (CA can't invent capacity a node group
          doesn't have room to add)
```

Scale-**down** works in reverse: CA watches for nodes that are
underutilized for a sustained window and whose Pods could all fit
elsewhere, cordons and drains that node (Day 08's `ex01`/`ex02`, for real,
because now there IS somewhere else to reschedule to), then removes it via
the same provider API.

## What this actually needs, that this course's VM doesn't have

| Requirement | This course's VM |
|---|---|
| A node **group/pool** with a min/max size CA can scale between | One fixed VM, provisioned once by hand |
| A cloud-provider (or on-prem: Cluster API, etc.) integration CA calls to add/remove nodes | None — no provisioning API behind this node at all |
| Capacity to actually add a node when needed | N/A |

This is the same category of gap Day 04 hit with CNI migration and Day 08
hit with a real k3s version upgrade: real, useful content that a single
fixed node cannot **execute**, only describe accurately.

## How HPA/VPA (real, this cluster) and CA (concept only) fit together

```text
Pod resource USAGE changes
        |
        v
  VPA (ex03) -> right-sizes each Pod's requests/limits
  HPA (ex02) -> changes how many Pods there are
        |
        v
If the EXISTING node(s) can't fit the new Pod count/size:
        |
        v
  Cluster Autoscaler -> changes how many NODES there are
```

HPA and VPA answer "how much of what's already here should this workload
use." Cluster Autoscaler answers "is there enough 'here' at all" — a
question this course's one-node cluster structurally cannot ask itself,
because there's no elastic pool of capacity behind it to add to.

## On-prem / bare-metal note

Cluster Autoscaler isn't cloud-exclusive — it has provider implementations
for on-prem tooling too (e.g. Cluster API-based providers), and there are
non-CA approaches for physical capacity (pre-provisioned spare hardware
joined manually, exactly how Day 00 joined this course's one node). The
concept transfers; the mechanism this course could exercise live does not,
for the same reason a single VM can't demonstrate what happens when you buy
a second one.

## Discussion prompts

1. If this course had a second identical VM sitting powered-off, what
   would be the **minimum** additional tooling needed to let Cluster
   Autoscaler power it on and join it automatically, versus doing that by
   hand (Day 00's install script, again, on a second machine)?
2. HPA (`ex02`) hit its `maxReplicas: 5` ceiling under load and stayed
   there rather than overshooting. If Cluster Autoscaler had been available
   and configured, what should have happened differently at that ceiling?
3. Why does scale-**down** for Cluster Autoscaler need to check "could
   every Pod on this node fit elsewhere" before removing a node, when HPA's
   scale-down (`ex02`) only needs to check a single utilization number?
