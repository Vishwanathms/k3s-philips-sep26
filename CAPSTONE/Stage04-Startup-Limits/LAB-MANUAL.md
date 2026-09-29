# Capstone stage 04 — Startup probes and what limits really do

## Scenario

Stage 03 gave every tier probes, requests and limits. Two things are still
missing from Day 07. First, the app has no protection for a **slow start**:
a strict liveness probe would kill any Pod that takes too long to boot.
Second, the limits are only numbers so far. You haven't yet watched a CPU
limit throttle the API or a memory limit kill it.

In this stage you add startup probes to the app, then break it on purpose to
see each limit and QoS rule do its job.

## What changed since Stage 03

| File | Change |
|---|---|
| `manifests/10-redis.yaml` | `startupProbe` (`redis-cli ping`, up to 60s); liveness loses `initialDelaySeconds` |
| `manifests/20-api.yaml` | `startupProbe` (`/healthz`, up to 60s); liveness loses `initialDelaySeconds` |
| `drills/api-slow-*.yaml` | throwaway slow-booting API, with and without a startup probe (S1) |

Everything else is identical to Stage 03.

## Learning objectives

- explain why a startup probe exists, and size its budget with margin
- see CPU limits **throttle** a container (cgroup `cpu.stat`), not kill it
- see a memory limit **kill** a container (`OOMKilled`, exit 137) while the app stays up
- tell a Pod **rejected at admission** (LimitRange/quota) from one **Pending at scheduling** (`Insufficient cpu`)
- read `oom_score_adj` for each QoS class, the kernel value behind "BestEffort dies first"

## Before starting

Stage 03 running (or catch up with it):

```bash
cd ~/Documents/k3s-training
kubectl apply -f CAPSTONE/Stage03-Health/manifests/
kubectl -n capstone get pods          # 5 Pods 1/1 Running
export NODE_IP=$(hostname -I | awk '{print $1}')
```

---

## S0 — Deploy Stage 04 (5 min)

```bash
cd CAPSTONE/Stage04-Startup-Limits
kubectl apply -f manifests/
kubectl -n capstone rollout status statefulset/redis
kubectl -n capstone rollout status deploy/api
kubectl -n capstone describe pod -l app=api | grep -E '^Name:|Startup:|Liveness:'
curl -s --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits; echo
```

Expected:

```
Name:             api-...
    Liveness:   http-get http://:http/healthz delay=0s timeout=1s period=10s #success=1 #failure=3
    Startup:    http-get http://:http/healthz delay=0s timeout=1s period=2s #success=1 #failure=30
{"hits":..,"pod":"api-...","version":"1.0.0"}
```

How the probes work together:

| Probe | Runs | On failure |
|---|---|---|
| startup | from container start until it first passes (max `30 × 2s = 60s`) | container restarted |
| liveness | only **after** startup passed | container restarted |
| readiness | only **after** startup passed | Pod removed from Service endpoints |

Liveness no longer needs `initialDelaySeconds`: the startup probe holds it
back until the app is up, however long that takes (within the budget).

> **Checkpoint S0:** both api Pods show a `Startup:` line, and the counter
> continued from Stage 03.

## S1 — Drill: a slow start, with and without a startup probe (10 min)

`drills/` has the same API image with a command that sleeps 30s before
starting gunicorn, like an app that loads a model or warms a cache at boot.
It needs about 40s in total. Both files deploy a Deployment `api-slow` that
the `api` Service never routes to.

**S1a — only a liveness probe** (first check at 5s, killed after 3 failures
10s apart, so at about 25s):

```bash
kubectl apply -f drills/api-slow-no-startup.yaml
kubectl -n capstone get pods -l app=api-slow -w      # watch ~2.5 min, then Ctrl-C
```

Expected: `READY` stays `0/1`, `RESTARTS` climbs, and `STATUS` alternates
between `Running` and `CrashLoopBackOff`. It never comes up:

```
api-slow-...   0/1   Running            4 (29s ago)   2m30s
```

```bash
P=$(kubectl -n capstone get pod -l app=api-slow -o name)
kubectl -n capstone describe $P | grep -E 'Exit Code|Restart Count'
kubectl -n capstone describe $P | grep -E 'Liveness probe failed|Killing' | tail -2
```

```
      Exit Code:    143
    Restart Count:  4
  Warning  Unhealthy  ...  Liveness probe failed: Get "http://10.42.0.217:8000/healthz": dial tcp ...: connect: connection refused
  Normal   Killing    ...  Container api failed liveness probe, will be restarted
```

Exit code 143 = 128 + 15 (SIGTERM): the kubelet stopped it. The liveness
probe is doing exactly what you told it to; it just can't tell "still
booting" from "hung".

**S1b — the same app plus a startup probe** (up to `45 × 2s = 90s`):

```bash
kubectl -n capstone delete deploy api-slow
kubectl apply -f drills/api-slow-with-startup.yaml
kubectl -n capstone rollout status deploy/api-slow --timeout=150s
kubectl -n capstone get pods -l app=api-slow
kubectl -n capstone describe pod -l app=api-slow | grep -E 'Restart Count|Startup probe failed'
```

Expected: `1/1 Running`, `0` restarts, after about 50s. The startup probe
failed about 25 times while the app booted, and that was fine: it had 45.

```
api-slow-...   1/1   Running   0   53s
    Restart Count:  0
  Warning  Unhealthy  ...  (x20 over 52s)  Startup probe failed: ... connect: connection refused
```

**Size the budget with margin.** While building this drill, a 45s sleep
with a 60s budget failed: under its 200m CPU limit, gunicorn took another
~9s to boot, so the app answered at ~54s. That left too little margin, and
the startup probe gave up at 60s. Boot is slower on a busy node or a tight CPU limit.
Measure it, then allow roughly double.

```bash
kubectl -n capstone delete deploy api-slow
```

> **Checkpoint S1:** you can say why S1a never starts and S1b does, using the
> words "liveness" and "startup budget".

## S2 — Drill: a CPU limit throttles (5 min)

Each API container has `limits.cpu: 500m`. The kernel enforces that as a
quota: 50ms of CPU in every 100ms period. `/api/cpu?ms=2000` busy-loops for
2 seconds of wall time on one thread, so it **wants** a full core.

```bash
P=$(kubectl -n capstone get pod -l app=api -o jsonpath='{.items[0].metadata.name}')
kubectl -n capstone exec $P -- cat /sys/fs/cgroup/cpu.max
kubectl -n capstone port-forward pod/$P 18000:8000 >/dev/null &
S() { kubectl -n capstone exec $P -- grep -E 'usage_usec|nr_periods|nr_throttled' /sys/fs/cgroup/cpu.stat | tr '\n' ' '; echo; }
S
curl -s "http://localhost:18000/api/cpu?ms=2000"; echo
S
kill %1
```

Expected:

```
50000 100000
usage_usec 6216994 nr_periods 884 nr_throttled 88 ...
{"burned_ms":2000,"loops":2706023,"pod":"api-..."}
usage_usec 7282562 nr_periods 907 nr_throttled 109 ...
```

Read it: 2 seconds of wall time, but `usage_usec` rose by only ~1,070,000
(about 1 second of CPU), and 21 of the 23 periods were throttled. The request
got **half a core**, as the limit says. Nothing was killed: a CPU limit
makes the container **slower**, never dead. (The request goes through
`port-forward` so the client's own CPU isn't counted in the container's
cgroup.)

> **Checkpoint S2:** `nr_throttled` went up, and the request finished but
> used only about half the CPU time it asked for.

## S3 — Drill: a memory limit kills (5 min)

Each API container has `limits.memory: 256Mi`. Simulate a memory leak inside
one API Pod:

```bash
P=$(kubectl -n capstone get pod -l app=api -o jsonpath='{.items[1].metadata.name}')
kubectl -n capstone exec $P -- cat /sys/fs/cgroup/memory.max
kubectl -n capstone exec $P -- python -c '
import time; b = []
for i in range(40):
    b.append(bytearray(16 * 1024 * 1024)); print((i + 1) * 16, "MiB", flush=True); time.sleep(0.1)'
```

Expected: it counts up to about 176 MiB (gunicorn already uses ~65 MiB),
then `command terminated with exit code 137`.

```bash
kubectl -n capstone get pods -l app=api
kubectl -n capstone get pod $P -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}{" exit="}{.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
for i in 1 2 3; do curl -s --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits; echo; done
```

Expected:

```
api-...-5f8gl   1/1   Running   0            15m
api-...-rn48s   0/1   Running   1 (6s ago)   15m
OOMKilled exit=137
{"hits":28,"pod":"api-...-5f8gl","version":"1.0.0"}
...
```

Exit 137 = 128 + 9 (SIGKILL) from the kernel's OOM killer. The **whole
container** was killed, not just the leaking process: Kubernetes sets
`memory.oom.group=1` on the container's cgroup. The kubelet restarted it,
its startup probe covered the reboot, and meanwhile the **other** API Pod
kept serving. That's why the api tier runs 2 replicas.

> **Checkpoint S3:** the Pod's last state is `OOMKilled`, it restarted, and
> the counter kept going throughout.

## S4 — Drill: rejected at admission vs Pending at scheduling (5 min)

Ask for 8 CPUs on a node that has 4. First, in `capstone`:

```bash
kubectl get node -o jsonpath='{.items[0].status.allocatable.cpu}{" cpu allocatable\n"}'
kubectl -n capstone run big --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"big","image":"busybox:1.36","command":["sleep","60"],"resources":{"requests":{"cpu":"8"},"limits":{"cpu":"8"}}}]}}'
```

Expected: refused on the spot, no Pod is created:

```
Error from server (Forbidden): pods "big" is forbidden: maximum cpu usage per Container is 1, but limit is 8
```

Now in a scratch namespace with **no** LimitRange or quota:

```bash
kubectl create namespace capstone-scratch
kubectl -n capstone-scratch run big --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"big","image":"busybox:1.36","command":["sleep","60"],"resources":{"requests":{"cpu":"8"}}}]}}'
kubectl -n capstone-scratch get pod big
kubectl -n capstone-scratch get events --field-selector reason=FailedScheduling -o custom-columns=MSG:.message
```

Expected: the Pod **is** created, but stays Pending:

```
big    0/1     Pending   0          6s
0/1 nodes are available: 1 Insufficient cpu. ...
```

| | Who says no | When | What you see |
|---|---|---|---|
| LimitRange / ResourceQuota | API server (admission) | at `kubectl apply` | `Forbidden`, no Pod object |
| Not enough node capacity | scheduler | after the Pod exists | Pod `Pending`, event `Insufficient cpu` |

Requests are what the scheduler adds up. Usage doesn't matter: a node can
be idle and still have no room left to *reserve*.

> **Checkpoint S4:** you can say which component refused each Pod.

Keep `capstone-scratch` for S5.

## S5 — Drill: QoS and `oom_score_adj` (5 min)

When a node runs out of memory, the kernel picks a victim by
`oom_score_adj` (-1000 … 1000, higher dies first). The kubelet sets it from
the Pod's QoS class. `capstone` can't hold a BestEffort Pod (the LimitRange
fills in defaults), so borrow the scratch namespace for one:

```bash
kubectl -n capstone-scratch run besteffort --image=busybox:1.36 --restart=Never -- sleep 120
kubectl -n capstone-scratch wait --for=condition=Ready pod/besteffort --timeout=60s
for p in capstone/redis-0 \
         capstone/$(kubectl -n capstone get pod -l app=api -o jsonpath='{.items[0].metadata.name}') \
         capstone/$(kubectl -n capstone get pod -l app=web -o jsonpath='{.items[0].metadata.name}') \
         capstone-scratch/besteffort; do
  ns=${p%/*}; n=${p#*/}
  printf '%-26s %-11s oom_score_adj=%s\n' $n $(kubectl -n $ns get pod $n -o jsonpath='{.status.qosClass}') $(kubectl -n $ns exec $n -- cat /proc/1/oom_score_adj)
done
```

Expected:

```
redis-0                    Guaranteed  oom_score_adj=-997
api-...                    Burstable   oom_score_adj=998
web-...                    Burstable   oom_score_adj=999
besteffort                 BestEffort  oom_score_adj=1000
```

| QoS | `oom_score_adj` | Meaning |
|---|---|---|
| Guaranteed | -997 | killed last, just before system daemons |
| Burstable | 2 … 999 | the more memory it requests, the lower the value |
| BestEffort | 1000 | killed first |

This is why redis, the one tier holding data, is Guaranteed.

```bash
kubectl delete namespace capstone-scratch
```

> **Checkpoint S5:** you can predict the order the kernel would kill these
> four Pods in.

---

## Troubleshooting

| Symptom | Likely cause / check |
|---|---|
| S1b also restarts (`failed startup probe`) | boot took longer than the startup budget, often a busy node. Check `kubectl logs` timestamps; raise `failureThreshold` |
| S1a shows `1/1` or boots before being killed | the container ignores SIGTERM. The drill's command uses `trap` + `sleep & wait` for this reason |
| S2 `nr_throttled` barely moves | the request went to the other Pod. Use `port-forward` to the Pod you measure |
| S3 prints all 40 lines and nothing dies | you ran it in a Pod with a higher memory limit, or in `web`. Use an api Pod (256Mi) |
| `exceeded quota` while running the drills | `api-slow` from S1 still exists: `kubectl -n capstone delete deploy api-slow` |
| scratch namespace stuck `Terminating` | wait; the busybox Pods take up to 30s to stop |

## Before you leave — keep it running

Stage 04 is the app Day 08 starts from:
[Stage 05](../Stage05-Disruption-Backup-Restore/LAB-MANUAL.md) (disruption budgets,
backup and restore). To catch up later:

```bash
kubectl apply -f CAPSTONE/Stage04-Startup-Limits/manifests/
```
