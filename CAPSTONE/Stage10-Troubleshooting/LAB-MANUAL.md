# Capstone stage 10 — Find it, fix it (Day 12)

## Scenario

Monday morning: the capstone app is reported broken. Nobody tells you what
changed. Five real mistakes landed on the cluster at once — the kind that
actually happen (a typo in a selector, a bad release tag, a policy that
doesn't match the code, a resource limit set too tight, a probe path with
a typo). Nothing here is fake or simulated: every symptom below is a real
Kubernetes object doing exactly what it was told.

Your job: find all five, fix them one at a time, and prove the app is
healthy — without deleting and recreating anything. This is a **read-only
diagnosis, targeted fix** exercise, the discipline Day 12 built lab by lab.

## What changed since Stage 09

Nothing in `manifests/` — this stage is a full snapshot of Stage 09's
build, unchanged. The only new things are two scripts:

| File | Purpose |
|---|---|
| `scripts/break-capstone.sh` | **instructor-run once**, injects the 5 faults into the live cluster via `kubectl patch`/`set image` — no file in this repo is ever wrong |
| `scripts/verify-capstone.sh` | **student-run at the end**, checks all 5 symptoms are actually gone, not just "Pods exist" |

## Learning objectives

- diagnose from evidence, in the order Day 12 taught: `get pods` →
  `describe` (Events) → `get endpoints` → logs → one layer deeper only if
  needed
- distinguish a Service-selector mismatch from a readiness-probe failure —
  both end in "no traffic reaches the Pods", with different fixes
- read a stuck Deployment rollout and explain why the old ReplicaSet
  hasn't been scaled down yet
- recognize `OOMKilled` (`Last State`, exit code 137) and separate it from
  a crash in application code
- see one fault cascade into a second symptom on an unrelated object, and
  trace it back to its real root cause

## Before starting

Stage 09 running (or catch up with its manual):

```bash
cd ~/Documents/k3s-training/CAPSTONE/Stage10-Troubleshooting
export NS=capstone
export NODE_IP=$(hostname -I | awk '{print $1}')
kubectl -n "$NS" get pods              # 6 Pods, all 2/2 Running
curl -s -H 'Host: capstone.k3s.local' http://$NODE_IP/api/hits   # counter works
```

**Instructor runs this once, right before the lab:**

```bash
./scripts/break-capstone.sh
```

Students should **not** read the script before diagnosing — that's the
whole exercise. (For self-paced study, read it after finishing T1–T5.)

---

## First look (5 min)

```bash
kubectl -n "$NS" get pods,svc,endpoints
curl -sf -m5 -H 'Host: capstone.k3s.local' http://$NODE_IP/ ; echo " -> $?"
```

Expected right after the break:

```
NAME                          READY   STATUS             RESTARTS   AGE
pod/api-...-4wrvq             1/2     Running            0          ...
pod/api-...-g2gng             1/2     Running            0          ...
pod/api-...-7lgqm             1/2     ImagePullBackOff   0          ...
pod/redis-0                   1/2     CrashLoopBackOff   2 (..)     ...
pod/web-...-2bcgz             2/2     Running            0          ...
pod/web-...-grcjl             2/2     Running            0          ...
pod/web-...-b6vnn             1/2     Running            0          ...

NAME              ENDPOINTS   AGE
endpoints/api                 23h
endpoints/redis               23h
endpoints/web     <none>      23h

-> 000   (curl times out: Traefik has no backend to send this to)
```

Three Pods are unhealthy in three different ways, and **two Services have
no endpoints** even though Pods matching their app look like they exist.
That's five things, not one — resist fixing the first thing you see and
declaring victory.

> **Checkpoint:** you can list, from `get pods` alone, which Pod(s) look
> wrong and in what way (crash-looping / image error / not-Ready).

## T1 — `endpoints/web` has none, but web Pods are Running (10 min)

```bash
kubectl -n "$NS" get pods -l app=web
kubectl -n "$NS" get svc web -o jsonpath='{.spec.selector}{"\n"}'
kubectl -n "$NS" get pods -l app=web --show-labels
```

Expected:

```
web-...-2bcgz   2/2   Running
web-...-grcjl   2/2   Running
web-...-b6vnn   1/2   Running

{"app":"web-tier"}

NAME            LABELS
web-...-2bcgz   ...,app=web,tier=web,...
```

The Service selects `app=web-tier`. Every web Pod is labelled `app=web`.
Zero Pods can ever match — this is a typo, not a scheduling or networking
problem, and `describe service` would show it too (`Endpoints: <none>`
next to the selector).

```bash
kubectl -n "$NS" patch service web --type=merge -p '{"spec":{"selector":{"app":"web"}}}'
kubectl -n "$NS" get endpoints web
```

Expected: `web   10.42.0.46:8080,10.42.0.49:8080` — **two** addresses, not
three. The third web Pod is still `1/2`, so it's correctly left out. That's
the next fault.

> **Checkpoint T1:** you can say why `get endpoints` returning nothing is
> a Service problem, not a Pod problem — and why fixing it only recovered
> 2 of 3 web Pods.

## T2 — a web Pod stuck `1/2` with no restarts (10 min)

```bash
kubectl -n "$NS" get pods -l app=web
kubectl -n "$NS" describe pod -l app=web   # find the 1/2 one, read its Events
```

Expected (the last two lines are what matters — read them in order):

```
Warning  Unhealthy  ...  Readiness probe failed: HTTP probe failed with statuscode: 502
Warning  Unhealthy  ...  Readiness probe failed: HTTP probe failed with statuscode: 404
```

No restarts, because a readiness failure never restarts a container — only
`livenessProbe` does that. nginx itself is running fine; something is
asking it for a URL it doesn't serve.

```bash
kubectl -n "$NS" get deploy web -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}{"\n"}'
```

Expected: `/healthzz` — an extra `z`. Fix it and watch the rollout, not
just the Pod:

```bash
kubectl -n "$NS" patch deployment web --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/healthz"}]'
kubectl -n "$NS" rollout status deploy/web --timeout=60s
```

Expected: `deployment "web" successfully rolled out`. `web` is now fully
fixed.

> **Checkpoint T2:** you can explain why 0 restarts ruled out a crash
> before you even read the Events.

## T3 — a Pod that never left `ImagePullBackOff` (10 min)

```bash
kubectl -n "$NS" get pods -l app=api
kubectl -n "$NS" get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Expected:

```
api-...-4wrvq   1/2   Running            0
api-...-g2gng   1/2   Running            0
api-...-7lgqm   1/2   ImagePullBackOff   0

localhost:5000/capstone-api:9.9.9-missing
```

Notice the **other two** api Pods are also `1/2`, still `Running` — that's
a different, unrelated fault (T5). Don't fix this one yet by touching those
Pods; fix only what T3's evidence points at: the tag.

```bash
kubectl -n "$NS" set image deployment/api api=localhost:5000/capstone-api:1.0.0
kubectl -n "$NS" get rs -l app=api                        # the bad ReplicaSet, desired 0
```

The rollout stays incomplete for now (`rollout status` times out) — the
Deployment won't finish replacing Pods while **every** api Pod, old and
new, is failing readiness. That's expected: it's T5's fault, not this fix
failing. Move on.

> **Checkpoint T3:** you can explain why Docker Hub-style "not found" and
> "wrong tag" look identical here too (Day 12 ex05), and why the rollout
> didn't finish the moment you fixed the tag.

## T4 — redis `CrashLoopBackOff`, no code changed (10 min)

```bash
kubectl -n "$NS" get pod redis-0
kubectl -n "$NS" describe pod redis-0    # find "Last State"
```

Expected:

```
redis-0   1/2   CrashLoopBackOff   4 (60s ago)   6m

Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
```

`OOMKilled` + exit code 137 is always the kernel killing the process for
using more memory than its limit — never an application bug to chase in
the code.

```bash
kubectl -n "$NS" get statefulset redis -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
```

Expected: `{"limits":{"cpu":"100m","memory":"8Mi"},"requests":{"cpu":"100m","memory":"8Mi"}}`
— 8Mi for a redis instance that already holds real data. Restore Stage 09's
value:

```bash
kubectl -n "$NS" patch statefulset redis --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"128Mi"},
       {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"128Mi"}]'
kubectl -n "$NS" delete pod redis-0     # StatefulSets don't auto-recreate on a spec-only change until the next restart trigger
kubectl -n "$NS" rollout status statefulset/redis --timeout=90s
```

Expected: `partitioned roll out complete`, then `redis-0 2/2 Running`,
`RESTARTS 0`.

> **Checkpoint T4:** you can say why raising the limit, not restarting
> redis harder, was the actual fix.

## T5 — everything recovers, but check the cascade (10 min)

```bash
kubectl -n "$NS" get pods
kubectl -n "$NS" rollout status deploy/api --timeout=60s
kubectl -n "$NS" get endpoints api
```

Expected: within about 30 seconds of T4's fix, api's rollout — stuck since
T3 — completes on its own, and `endpoints/api` fills back in. The api
Pods' `/ready` probe calls redis; while redis was down, **every** api Pod
(old and new) was `1/2`, which is also why the Deployment refused to
finish scaling down the bad ReplicaSet — it never saw a healthy replacement
to hand traffic to. One root cause (T4) was hiding behind two symptoms
(api endpoints, a stuck rollout) that had nothing to do with the api
manifest itself.

Now the last piece: a NetworkPolicy nobody would notice from `get pods` at
all.

```bash
kubectl -n "$NS" exec deploy/web -c web -- wget -q -T3 -O- http://api:8000/api/info
```

Expected: `wget: server returned error: HTTP/1.1 503 Service Unavailable`
— even with every Pod healthy. Requests, endpoints and Pods all look fine;
the traffic just doesn't arrive. That rules out everything except a
policy.

```bash
kubectl -n "$NS" get networkpolicy api -o jsonpath='{.spec.ingress[0].ports}{"\n"}'
```

Expected: `[{"port":8001,"protocol":"TCP"},{"port":4143,"protocol":"TCP"}]`
— the policy allows port 8001 in; the container listens on 8000.

```bash
kubectl -n "$NS" patch networkpolicy api --type=json \
  -p='[{"op":"replace","path":"/spec/ingress/0/ports/0/port","value":8000}]'
kubectl -n "$NS" exec deploy/web -c web -- wget -q -T3 -O- http://api:8000/api/info
```

Expected: `{"pod":"api-...","redis":"redis:6379","version":"1.0.0"}`.

> **Checkpoint T5:** you can say why this fault gave the *identical*
> symptom (503/504, no useful Event) whether the port mismatch was in the
> NetworkPolicy or the container itself — and which `kubectl` command
> distinguishes them (`get networkpolicy -o yaml` vs. `get pod -o yaml`
> for the container port).

---

## Prove it (5 min)

```bash
./scripts/verify-capstone.sh
curl -s -H 'Host: capstone.k3s.local' http://$NODE_IP/api/hits; echo
```

Expected: `== ALL CHECKS PASS`, and the counter is **higher** than before
`break-capstone.sh` ran — loadgen kept incrementing it the entire time,
proof nothing was reset or restored from a backup.

Write down, in your own words, the root cause of each of the 5 faults —
this is the deliverable, not just a green check.

---

## Troubleshooting

| Symptom | Likely cause / check |
|---|---|
| `verify-capstone.sh` still fails after all 5 fixes | re-run `kubectl -n capstone get pods,svc,endpoints` from the top — a rollout may still be catching up |
| api rollout never finishes even after T3 | it won't, until T4 is also fixed: the RollingUpdate strategy won't remove the old ReplicaSet's Pod while the new one still can't pass readiness (which needs redis) |
| `kubectl exec ... redis-cli` fails with "possibly OOM-killed" | you're mid-crash-loop; wait for T4's fix, or retry after `rollout status statefulset/redis` returns |
| fixed the NetworkPolicy but web→api still fails | check you edited `ingress[0].ports[0]`, not `egress` — `kubectl -n capstone get networkpolicy api -o yaml` |
| `patch ... --type=json` errors with "test failed" or path not found | field doesn't exist at that index anymore — re-check with `-o jsonpath` first, a fix (or the instructor's script) may already have changed the shape |

## Before you leave — keep it running

This stage adds nothing permanent. Keep the namespace as fixed: every
later stage assumes a healthy `capstone`. To catch up later:

```bash
kubectl apply -f CAPSTONE/Stage10-Troubleshooting/manifests/
# if a break is still active, fix it by hand using T1-T5 above, or:
kubectl -n capstone patch service web --type=merge -p '{"spec":{"selector":{"app":"web"}}}'
kubectl -n capstone patch deployment web --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/healthz"}]'
kubectl -n capstone set image deployment/api api=localhost:5000/capstone-api:1.0.0
kubectl -n capstone patch networkpolicy api --type=json -p='[{"op":"replace","path":"/spec/ingress/0/ports/0/port","value":8000}]'
kubectl -n capstone patch statefulset redis --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"128Mi"},{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"128Mi"}]'
kubectl -n capstone delete pod redis-0
```
