# ex05 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`.
Result: **PASS** — a capacity prediction computed from this node's real,
current numbers was confirmed exactly against the real scheduler.

## A real gap worth knowing about first

```console
$ kubectl top node
NAME         CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
lab-g2-vm2   1114m        27%      7363Mi          62%

$ kubectl describe node | grep -A6 "Allocated resources"
Allocated resources:
  Resource   Requests    Limits
  --------   --------    ------
  cpu        280m (7%)   0 (0%)
  memory     300Mi (2%)  1970Mi (16%)
```

**27% real CPU use vs. 7% "allocated"; 62% real memory vs. 2% "allocated."**
This isn't a measurement error — `kubectl describe node`'s "Allocated
resources" is the **scheduler's bookkeeping** (the sum of every Pod's
`requests`), while `kubectl top node` is **actual live usage**. They can
differ enormously:

```console
$ kubectl -n kube-system get pods -o jsonpath='{range .items[*]}{.metadata.name}{" cpu-req="}{.spec.containers[0].resources.requests.cpu}{"\n"}{end}' | grep vpa
vpa-...-admission-controller-...   cpu-req=
vpa-...-admission-controller-...   cpu-req=
vpa-...-recommender-...             cpu-req=
vpa-...-recommender-...             cpu-req=
vpa-...-updater-...                 cpu-req=
vpa-...-updater-...                 cpu-req=
```

All six VPA Pods (`ex03`) run with **no `requests` set at all** — real
CPU/memory the node is genuinely spending, contributing **zero** to the
scheduler's picture of what's "used." Capacity planning off `describe
node`'s percentages alone would have missed a real and current example
sitting on this exact cluster.

## The math, computed from this node's real numbers

```console
$ bash ex05-capacity-planning/capacity-math.sh 250 256
Node allocatable:      4 CPU, 11766Mi memory
Already requested:     280m CPU, 300Mi memory
Free by request math:  3720m CPU, 11466Mi memory

A Pod requesting 250m CPU / 256Mi memory:
  fits 14 more times by CPU
  fits 44 more times by memory
  -> CPU is the binding constraint: predict 14 Pods schedule, the next one(s) go Pending
```

## The prediction, tested against the real scheduler

```console
$ kubectl apply -f ex05-capacity-planning/verify-prediction.yaml   # 16 replicas requested
deployment.apps/capacity-test created

$ kubectl get pods -l app=capacity-test --no-headers | awk '{print $3}' | sort | uniq -c
     14 Running
      2 Pending

$ kubectl describe pod <a Pending one> | tail -3
Warning  FailedScheduling  10s  default-scheduler  0/1 nodes are available: 1 Insufficient cpu.
  no new claims to deallocate, preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.
```

**Exactly 14 Running, exactly 2 Pending** — the request-based math predicted
the scheduler's real behavior precisely, and the failure reason on the
overflow Pods (`Insufficient cpu`) matches the constraint the math
identified as binding.

## The capacity-planning takeaway

Request-based math (`describe node`, this script) tells you exactly what
the **scheduler** will allow — and it's provably accurate for that
question. It does **not** tell you whether the node can handle that many
Pods' **real** resource usage without contention, especially when — as
demonstrated above, on this very node — some real Pods carry no requests
at all and are invisible to that arithmetic. Real capacity planning needs
both numbers: `describe node` for "will it schedule," `top node`/`top pod`
for "will it actually perform once it does."
