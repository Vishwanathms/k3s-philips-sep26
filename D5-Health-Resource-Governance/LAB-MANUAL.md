# D5 lab manual — Health Management & Resource Governance

## Learning objectives

By the end of this lab, students can choose between liveness/readiness/
startup probes for a given failure mode, explain what CPU vs memory limits
actually enforce (throttling vs killing) and read the kernel-level evidence
for both, use `ResourceQuota`/`LimitRange` to govern a namespace, and
explain what determines a Pod's QoS class and why that class matters when a
node runs low on resources.

## Before starting

Every path below is relative to this folder, so start here:

```bash
cd D5-Health-Resource-Governance
kubectl apply -f 00-namespace.yaml
export NS=d5-health
kubectl describe node | grep -A6 Allocatable   # note this node's real CPU/memory ceiling
```

---

## Lab 1 — Liveness probe: kills and restarts

```bash
kubectl apply -f ex01-liveness-probe/pod.yaml
kubectl wait --for=condition=Ready pod/liveness-demo -n "$NS" --timeout=30s
kubectl get pod liveness-demo -n "$NS"        # RESTARTS: 0
```

The container touches `/tmp/healthy`, sleeps 30s, then deletes it and sleeps
forever — silently broken from that point on. The liveness probe
(`cat /tmp/healthy`, `failureThreshold: 1`) is the only thing that notices:

```bash
sleep 45
kubectl get pod liveness-demo -n "$NS"                    # RESTARTS: 1
kubectl describe pod liveness-demo -n "$NS" | tail -10
# Warning  Unhealthy   Liveness probe failed: cat: can't open '/tmp/healthy'...
# Normal   Killing     Container app failed liveness probe, will be restarted
```

---

## Lab 2 — Readiness probe: reroutes, doesn't restart

```bash
kubectl apply -f ex02-readiness-probe/deployment.yaml
kubectl rollout status deployment/web -n "$NS" --timeout=60s
kubectl get endpointslice -l kubernetes.io/service-name=web -n "$NS" -o wide   # both Pods listed
```

Flip one replica's readiness marker off **without touching the container**:

```bash
POD=$(kubectl get pod -l app=web -n "$NS" -o jsonpath='{.items[0].metadata.name}')
kubectl exec "$POD" -n "$NS" -- rm /tmp/ready
sleep 6
kubectl get pods -l app=web -n "$NS"          # 0/1 Ready, RESTARTS still 0
kubectl exec "$POD" -n "$NS" -- ps aux        # nginx itself is fine
```

Prove traffic actually avoids it, then restore it:

```bash
kubectl run curl-test --image=busybox:1.36 --restart=Never --rm -i -n "$NS" -- \
  sh -c 'for i in 1 2 3 4 5; do wget -qO- http://web -T 3 >/dev/null 2>&1 && echo ok-$i || echo FAIL-$i; done'
kubectl exec "$POD" -n "$NS" -- touch /tmp/ready
```

---

## Lab 3 — Startup probe: protects a slow starter

Both Pods run the identical 20-second-to-heal container and the identical
liveness check — only `slow-starter-good` also has a `startupProbe`:

```bash
kubectl apply -f ex03-startup-probe/bad-no-startup-probe.yaml
kubectl apply -f ex03-startup-probe/good-with-startup-probe.yaml

sleep 60
kubectl get pod slow-starter-bad slow-starter-good -n "$NS"
# slow-starter-bad:   RESTARTS climbing (CrashLoopBackOff) - never gets 20s to finish starting
# slow-starter-good:  RESTARTS: 0 - the whole time

kubectl describe pod slow-starter-bad -n "$NS"  | grep -A3 Unhealthy   # "Liveness probe failed" + Killing
kubectl describe pod slow-starter-good -n "$NS" | grep -A3 Unhealthy   # "Startup probe failed" - no Killing
```

---

## Lab 4 — Requests and limits: three different consequences

**a) Requests drive scheduling:**

```bash
kubectl apply -f ex04-requests-limits/unschedulable.yaml
kubectl get pod too-big-to-schedule -n "$NS"                # Pending
kubectl describe pod too-big-to-schedule -n "$NS" | tail -3
# Warning  FailedScheduling  ... Insufficient cpu
kubectl delete -f ex04-requests-limits/unschedulable.yaml
```

**b) CPU limits throttle:**

```bash
kubectl apply -f ex04-requests-limits/cpu-throttle.yaml
kubectl wait --for=condition=Ready pod/cpu-throttle-demo -n "$NS" --timeout=30s
sleep 20
kubectl top pod cpu-throttle-demo -n "$NS"                  # pinned at the limit (200m)
kubectl exec cpu-throttle-demo -n "$NS" -- cat /sys/fs/cgroup/cpu.max     # 20000 100000
kubectl exec cpu-throttle-demo -n "$NS" -- cat /sys/fs/cgroup/cpu.stat    # nr_throttled > 0
kubectl delete -f ex04-requests-limits/cpu-throttle.yaml
```

**c) Memory limits kill:**

```bash
kubectl apply -f ex04-requests-limits/oom-kill.yaml
sleep 10
kubectl get pod oom-kill-demo -n "$NS"                       # STATUS: OOMKilled
kubectl get pod oom-kill-demo -n "$NS" -o jsonpath='{.status.containerStatuses[0].state.terminated}'
# exitCode 137, reason OOMKilled
kubectl delete -f ex04-requests-limits/oom-kill.yaml
```

---

## Lab 5 — `ResourceQuota` + `LimitRange`

```bash
kubectl apply -f ex05-resourcequota-limitrange/resourcequota.yaml
kubectl apply -f ex05-resourcequota-limitrange/limitrange.yaml

# a Pod with NO resources: block gets the LimitRange defaults auto-filled
kubectl run bare-pod --image=busybox:1.36 --restart=Never -n "$NS" -- sleep 3600
kubectl get pod bare-pod -n "$NS" -o jsonpath='{.spec.containers[0].resources}'

# below min / above max -> rejected at creation
kubectl run too-small -n "$NS" --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"c","image":"busybox:1.36","command":["sleep","3600"],"resources":{"requests":{"cpu":"1m","memory":"4Mi"}}}]}}'

# exhaust the namespace pod quota (hard cap: 3)
kubectl run bare-pod-2 --image=busybox:1.36 --restart=Never -n "$NS" -- sleep 3600
kubectl run bare-pod-3 --image=busybox:1.36 --restart=Never -n "$NS" -- sleep 3600
kubectl describe resourcequota team-quota -n "$NS"
kubectl run bare-pod-4 --image=busybox:1.36 --restart=Never -n "$NS" -- sleep 3600
# Error: exceeded quota: team-quota, requested: pods=1, used: pods=3, limited: pods=3
```

---

## Lab 6 — QoS classes

```bash
kubectl apply -f ex06-qos-classes/pods.yaml
kubectl get pods -l qos-demo=true -n "$NS" \
  -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass

for p in qos-guaranteed qos-burstable qos-besteffort; do
  echo "$p: $(kubectl exec $p -n "$NS" -- cat /proc/1/oom_score_adj)"
done
```

---

## Troubleshooting sequence

```bash
kubectl get pods -n <ns> -o wide
kubectl describe pod <name> -n <ns>              # events + Last State - the real reason is always here
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -20
kubectl top pod -n <ns>                          # needs metrics-server
kubectl exec <pod> -n <ns> -- cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/cpu.stat   # cgroup v2
```

| Symptom | Likely cause |
|---|---|
| `RESTARTS` climbing, `CrashLoopBackOff` | liveness probe failing, or the app itself crashing — check `describe` events and `Last State` |
| Pod `Running` but `0/1` Ready | readiness probe failing — check its own logic, not the container's health |
| Pod stuck `Pending`, `FailedScheduling` | requests exceed what any node can offer — check `describe node`'s `Allocatable` |
| Container repeatedly OOMKilled | memory limit too low for real usage, or a leak — `exitCode 137`/`reason OOMKilled` confirms it's the kernel, not the app, ending it |
| CPU-bound Pod feels "slow" but never crashes | check `cpu.stat`'s `nr_throttled`/`throttled_usec` — it's being paced, not failing |
| Pod creation `Forbidden` | `ResourceQuota` exhausted or `LimitRange` min/max violated — the message names which |
| A Pod got evicted before others when the node was under pressure | check `.status.qosClass` — `BestEffort` (`oom_score_adj` near `1000`) goes first, `Guaranteed` (near `-997`) goes last |

## Cleanup

```bash
kubectl delete namespace d5-health
```
