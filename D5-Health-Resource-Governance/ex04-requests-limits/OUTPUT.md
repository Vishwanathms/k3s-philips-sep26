# ex04 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1` (4 allocatable CPUs, single
node `lab-g2-vm2`), namespace `d5-health`. Result: **PASS** — three
different, real consequences of requests/limits: unschedulable, throttled,
and killed.

## a) Requests drive scheduling — `too-big-to-schedule`

```console
$ kubectl apply -f ex04-requests-limits/unschedulable.yaml
pod/too-big-to-schedule created

$ kubectl get pod too-big-to-schedule
NAME                  READY   STATUS    RESTARTS   AGE
too-big-to-schedule   0/1     Pending   0          5s

$ kubectl describe pod too-big-to-schedule
Events:
  Warning  FailedScheduling  5s  default-scheduler  0/1 nodes are available: 1 Insufficient cpu.
    no new claims to deallocate, preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
```

Requesting `cpu: "10"` on a 4-allocatable-CPU node: the scheduler can never
place it. It isn't "slow" or "stuck" — `Insufficient cpu` is the whole
story, right there in the event.

## b) Limits throttle CPU — `cpu-throttle-demo`

A tight busy-loop (`while true; do :; done`), capped at `limits.cpu: 200m`:

```console
$ kubectl apply -f ex04-requests-limits/cpu-throttle.yaml
$ kubectl top pod cpu-throttle-demo
NAME                CPU(cores)   MEMORY(bytes)
cpu-throttle-demo   200m         0Mi
```

Pinned at **exactly** the limit, no matter how hard it spins. The real
mechanism, read from the container's own cgroup v2 files:

```console
$ kubectl exec cpu-throttle-demo -- cat /sys/fs/cgroup/cpu.max
20000 100000                    # 20ms quota per 100ms period = 0.2 CPU = 200m

$ kubectl exec cpu-throttle-demo -- cat /sys/fs/cgroup/cpu.stat
nr_periods 170
nr_throttled 167                # 167 of the last 170 100ms windows were throttled
throttled_usec 3314146          # ~3.3s of accumulated throttled time
```

`limits.cpu` becomes a literal `cpu.max` quota the kernel's CFS bandwidth
controller enforces — no container-level awareness needed, and no process
gets killed for using "too much" CPU. It just gets paused until the next
period.

## c) Limits kill on memory — `oom-kill-demo`

```console
$ kubectl apply -f ex04-requests-limits/oom-kill.yaml
pod/oom-kill-demo created

$ kubectl get pod oom-kill-demo        # right after creation
NAME            READY   STATUS    RESTARTS   AGE
oom-kill-demo   1/1     Running   0          4s

$ kubectl get pod oom-kill-demo        # ~6s later, once it starts writing to tmpfs
NAME            READY   STATUS      RESTARTS   AGE
oom-kill-demo   0/1     OOMKilled   0          10s

$ kubectl get pod oom-kill-demo -o jsonpath='{.status.containerStatuses[0].state.terminated}'
{
    "exitCode": 137,
    "reason": "OOMKilled",
    "startedAt": "2026-09-13T07:18:54Z",
    "finishedAt": "2026-09-13T07:18:58Z"
}
```

`exitCode 137` = `128 + 9` (`SIGKILL`) — the kernel OOM-killer, not the
application, ended this process, the instant the container's cgroup crossed
its **20Mi** `memory` limit while writing to `/dev/shm` (tmpfs — real,
unswappable memory; this node also has swap off). There is no "slow down,
you're using too much memory" for memory the way there is for CPU — it's a
hard kill.

> **Why `/dev/shm`, not a regular file?** Writing to a normal file (`/tmp`)
> first was tried and did **not** OOM-kill — disk-backed page cache is
> reclaimable, so the kernel just wrote it out under pressure instead of
> invoking the OOM killer. `tmpfs` pages have nowhere to reclaim to (no
> swap), so they count as genuinely unrecoverable memory pressure — the
> realistic equivalent of a process's actual heap/anonymous memory growing
> past its limit.
