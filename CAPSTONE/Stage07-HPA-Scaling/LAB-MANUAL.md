# Capstone stage 07 — Autoscale the API under real load (Day 09)

## Scenario

Stage 06 showed that one noisy client can make **every** user slow: each API
Pod serves only 2 requests at a time (2 gunicorn workers), so requests queue.
Someone always has to run `kubectl scale` by hand when traffic grows.

In this stage the cluster does it itself. A **HorizontalPodAutoscaler** adds
API Pods when their CPU goes up and removes them when it drops. You drive
real load through the Ingress, watch it scale 2 → 6 → 2, and use Linkerd to
**prove** it helped the users. A **VerticalPodAutoscaler** also recommends
sizes for the tiers the HPA doesn't manage.

## What changed since Stage 06

| File | Change |
|---|---|
| `manifests/55-hpa-api.yaml` | **new**: HPA for `api`, 2–6 replicas, 60% of the api container's CPU request |
| `manifests/56-vpa-recommend.yaml` | **new**: VPA in recommend-only mode (`Off`) for `web` and `redis` |
| `manifests/20-api.yaml` | `replicas: 2` **removed**: the HPA owns the count now |
| `manifests/02-resourcequota.yaml` | `limits.cpu` 4 → 6, `limits.memory` 2Gi → 3Gi, `pods` 10 → 15, to fit 6 api Pods |
| `scripts/load.sh` | CPU load from outside the cluster, through the Ingress |

## Learning objectives

- write an `autoscaling/v2` HPA, and choose `ContainerResource` when Pods have sidecars
- explain why the Deployment must stop setting `replicas:`
- size a ResourceQuota for the HPA's **maximum**, not the current state
- watch scale-up and scale-down, and explain the stabilization window
- show with numbers (Linkerd) what scaling bought the users, and what it didn't
- read VPA recommendations critically, and explain why HPA and VPA must not share a resource

## Before starting

Stage 06 running, with Linkerd and viz (or catch up with Stage 06's manual):

```bash
cd ~/Documents/k3s-training/CAPSTONE/Stage07-HPA-Scaling
export PATH=$HOME/.linkerd2/bin:$PATH
export NODE_IP=$(hostname -I | awk '{print $1}')
kubectl -n capstone get pods                 # 6 Pods 2/2
kubectl top pods -n capstone | head -3       # metrics-server answers
kubectl get crd verticalpodautoscalers.autoscaling.k8s.io   # VPA from Day 09 ex03
```

No VPA CRD? Skip `56-vpa-recommend.yaml` (`kubectl apply` would fail on
it) and step H6. Everything else works without it.

---

## H1 — Read the HPA before you apply it (5 min)

```bash
cat manifests/55-hpa-api.yaml
```

| Field | Value | Why |
|---|---|---|
| `minReplicas` | 2 | never below 2: high availability, and the PDB (Stage 05) expects it |
| `maxReplicas` | 6 | the ResourceQuota is sized for exactly this (H2) |
| `metrics` | `ContainerResource`, container `api`, 60% | see below |
| `behavior.scaleDown.stabilizationWindowSeconds` | 60 | wait 60 s of low load before removing Pods (default 300 s) |

**Why `ContainerResource`?** Every api Pod also runs a `linkerd-proxy`
(Stage 06). The classic `type: Resource` averages the **whole Pod's** CPU
against the whole Pod's requests, so the proxy's work would count as if it
were the API's. `ContainerResource` looks at only the `api` container.

**60% of what?** Of the api container's **request**, 50m. So the HPA aims
for ~30m of CPU per Pod on average, and adds Pods when the average goes
above that:

```
desiredReplicas = ceil( currentReplicas × currentUtilization / 60% )
```

## H2 — The quota must fit the maximum (5 min)

Each extra api Pod costs **600m / 320Mi of limits** (api 500m/256Mi + proxy
100m/64Mi). Going from 2 to 6 api Pods adds 4 × 600m = 2400m, so limits
reach ~4550m, over Stage 06's `limits.cpu: 4`.

If the quota is too small, nothing warns you: the HPA sets `replicas: 6`,
the ReplicaSet gets `exceeded quota` on the extra Pods, and the app simply
stops growing early. So `02-resourcequota.yaml` grows to 6 CPU / 3Gi / 15
Pods. That covers 6 api Pods **plus** room for one rolling update (the
lesson from Stage 06).

## H3 — Apply (5 min)

```bash
kubectl apply -f manifests/
kubectl -n capstone get hpa api -w          # Ctrl-C after ~30 s
```

Expected:

```
NAME   REFERENCE        TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
api    Deployment/api   cpu: 18%/60%   2         6         2          42s
```

**Watch for a one-time dip to 1 replica.** `20-api.yaml` no longer has
`replicas:`, but the previous `kubectl apply` recorded `replicas: 2`. When a
field disappears from the file, `kubectl apply` **removes** it from the live
object, and a Deployment without `replicas` defaults to **1**. The HPA puts
it back to its minimum 2 within ~15 s:

```bash
kubectl -n capstone describe hpa api | grep -A3 Events
```

```
Normal  SuccessfulRescale  ...  New size: 2; reason: Current number of replicas below Spec.MinReplicas
```

It only happens on this first apply; later applies don't touch replicas.

> **Checkpoint H3:** the HPA shows a CPU percentage (not `<unknown>`) and 2
> replicas.

## H4 — Load it, watch it scale (10 min)

Two terminals. **Terminal 1**, the load: 4 parallel loops for 3 minutes,
each request asking for 200 ms of busy CPU, sent through the Ingress:

```bash
./scripts/load.sh 4 180 200
```

**Terminal 2**, the watch:

```bash
kubectl -n capstone get hpa api -w
```

Expected (15-second steps):

```
cpu: 11%/60%    2
cpu: 330%/60%   2        <- load arrives
cpu: 461%/60%   6        <- 2 -> 6 in one step
cpu: 383%/60%   6
...
cpu: 396%/60%   6        <- still above target: capped by maxReplicas
```

Why straight to 6? `ceil(2 × 461 / 60) = 16`, capped at `maxReplicas: 6`.
By default the HPA may double the Pods, or add 4, in each 15-second step,
whichever is more.

When the load script ends, keep watching:

```
cpu: 6%/60%     6
cpu: 9%/60%     6        <- low, but inside the 60 s stabilization window
cpu: 6%/60%     2        <- 6 -> 2
```

```bash
kubectl -n capstone describe hpa api | sed -n '/^Events:/,$p'
kubectl -n capstone describe quota capstone-quota
```

```
New size: 6; reason: cpu container resource utilization (percentage of request) above target
New size: 2; reason: All metrics below target
```

At 6 api Pods the quota showed `limits.cpu 4550m / 6`, `pods 10 / 15`,
exactly the H2 arithmetic.

> **Checkpoint H4:** you saw 2 → 6 → 2 and can explain both delays (15 s
> metric steps up, 60 s window down).

## H5 — Did it help? Prove it with Linkerd (15 min)

Scaling only helps when requests have to **wait**. Each api Pod runs 2
gunicorn workers, so it serves 2 requests at once. With 12 parallel loops, 2
Pods (4 slots) can't keep up and requests queue.

Run the same heavy load twice: once with the HPA **capped at 2**, once free
to reach 6. Read the numbers at ~80 s, while the load is running.

**Capped at 2:**

```bash
kubectl -n capstone patch hpa api --type merge -p '{"spec":{"maxReplicas":2}}'
./scripts/load.sh 12 100 200 &
sleep 80
kubectl -n capstone get hpa api
linkerd viz stat deploy/api -n capstone
linkerd viz stat deploy/loadgen -n capstone --to deploy/web
wait
```

**Free to 6** (wait until the HPA is back at 2 replicas first):

```bash
kubectl -n capstone patch hpa api --type merge -p '{"spec":{"maxReplicas":6}}'
./scripts/load.sh 12 100 200 &
sleep 80
kubectl -n capstone get hpa api
linkerd viz stat deploy/api -n capstone
linkerd viz stat deploy/loadgen -n capstone --to deploy/web
wait
```

Reference run:

| | replicas | api p50 / p95 | api RPS | **users** (loadgen → web) p50 / p95 |
|---|---|---|---|---|
| capped at 2 | 2 | 428 / 930 ms | 20.9 | 250 / 575 ms |
| HPA to 6 | 6 | 239 / 298 ms | 32.2 | **16 / 92 ms** |

Read it:
- The heavy requests can't get faster than ~200 ms: that's the work they
  asked for. But with 2 Pods they spent **another ~230 ms waiting** for a
  free worker. With 6 Pods the wait almost disappears.
- Throughput went up 50%: the same load is served faster, so more of it gets through.
- Normal users (`/api/hits` from `loadgen`) went from 250 ms to 16 ms.
  They were paying for other people's queue.

With only 4 parallel loops (H4) the same comparison shows almost no latency
difference: 4 requests fit into 2 Pods × 2 workers, nothing waits. More Pods
only help when requests are queueing.

Restore the file's settings:

```bash
kubectl apply -f manifests/55-hpa-api.yaml
```

> **Checkpoint H5:** you can explain why the users' latency improved 15×
> while the heavy requests' latency only halved.

## H6 — VPA: recommendations, read critically (5 min)

```bash
kubectl -n capstone get vpa
kubectl -n capstone get vpa web -o jsonpath='{.status.recommendation.containerRecommendations[0]}{"\n"}'
kubectl top pods -n capstone --containers | grep -E 'NAME|web'
```

Reference run:

```
NAME    MODE   CPU   MEM     PROVIDED   AGE
redis   Off    35m   250Mi   True       17m
web     Off    25m   250Mi   True       17m

{"containerName":"web","lowerBound":{"cpu":"25m","memory":"250Mi"},"target":{"cpu":"25m","memory":"250Mi"},...}

web-...   web   2m   4Mi
```

The VPA recommends **250Mi** for a container that uses **4Mi**. That's not
a measurement: 250Mi (and 25m CPU) is the recommender's **minimum**
(`--pod-recommendation-min-memory-mb=250` by default). Applied blindly, it
would raise web's memory request 8× and eat the quota. A recommendation is
input for a person, not a setting.

Why `Off` mode and why no VPA on `api`:
- `Off` only writes recommendations; `Auto`/`Recreate` would evict Pods to
  resize them.
- The HPA scales `api` on CPU **utilization = usage / request**. A VPA
  changing api's CPU request would move the HPA's measuring stick under it.
  Day 09 ex04 shows the safe combination: HPA on CPU, VPA on memory only.

> **Checkpoint H6:** you can say why the web recommendation is 250Mi, and
> why HPA and VPA must not both act on api's CPU.

---

## Troubleshooting

| Symptom | Likely cause / check |
|---|---|
| HPA `TARGETS` shows `<unknown>` | metrics-server isn't ready, or the Pods are too new. `kubectl top pods -n capstone`; wait 30–60 s |
| HPA stuck below max under load, Pods missing | quota: `kubectl -n capstone get events --field-selector reason=FailedCreate` shows `exceeded quota` |
| api drops to 1 Pod after an apply | the one-time `replicas` removal (H3). The HPA restores 2 within ~15 s |
| api jumps back to 2 during load after `kubectl apply` | an old `20-api.yaml` with `replicas: 2` was applied. Use this stage's file |
| no scale-down after the load | it waits 60 s of low CPU (the stabilization window), then drops to `minReplicas` |
| `load.sh`: no traffic reaches the api | `curl -s --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/info` must answer |
| `no matches for kind "VerticalPodAutoscaler"` | VPA isn't installed (Day 09 ex03). Delete `56-vpa-recommend.yaml` from your copy, or install VPA |

## Before you leave — keep it running

The HPA-managed app is the starting point for Day 10:
[Stage 08](../Stage08-Scheduling/LAB-MANUAL.md) (priorities, affinity, preemption). To catch
up later:

```bash
kubectl apply -f CAPSTONE/Stage07-HPA-Scaling/manifests/
```
