# Capstone stage 06 — See the latency of every hop (Linkerd service mesh)

## Scenario

Users say the capstone app "feels slow sometimes". `kubectl top` shows CPU,
the probes are green, the PDBs hold. None of that answers the real question:
**which hop is slow, and for whom?** Is it Traefik → web, web → api, or
api → redis?

You add a **service mesh**, Linkerd. It puts a small proxy next to every
Pod. The proxy sees every request that goes in or out, so without changing
the app you get, per hop:
- latency: p50 / p95 / p99
- success rate and requests per second
- mutual TLS between the Pods

Then you make the app slow on purpose and watch it happen.

> **Why not Hubble?** Hubble is the observability layer of the **Cilium**
> CNI. Using it means replacing k3s's built-in flannel network on the
> cluster, a disruptive change (see Day 04 `design-07-cni-comparison.md`).
> A mesh gives the same "latency per hop" view and leaves the cluster
> network alone.

## What changed since Stage 05

| File | Change |
|---|---|
| `manifests/00-namespace.yaml` | `linkerd.io/inject: enabled`, plus proxy CPU/memory annotations |
| `manifests/02-resourcequota.yaml` | `limits.cpu` 2 → 4 (a proxy per Pod, plus room for rolling updates) |
| `manifests/60-loadgen.yaml` | **new**: steady background traffic (~4 req/s through web) |
| `manifests/70-linkerd-viz-ingress.yaml` | **new**: the viz dashboard at `linkerd-viz.k3s.local` |
| `drills/loadgen-slow.yaml` | a client that asks for slow work (L3) |

The Deployments, StatefulSet and Services are identical to Stage 05.
Linkerd itself is installed with its own CLI (L1). It's cluster software,
not part of the capstone, so its YAML isn't kept in this folder.

## Learning objectives

- explain what a sidecar proxy is and what it can measure without code changes
- install Linkerd and its viz extension, and mesh one namespace
- size sidecars against a ResourceQuota, including rolling-update headroom
- read p50/p95/p99 latency per workload and per edge; tap live requests
- find a slow hop, and explain why a slow client makes **other** users slow
- say what a mesh can't see (opaque TCP like redis)

## Before starting

Stage 05 running (or catch up):

```bash
cd ~/Documents/k3s-training
kubectl apply -f CAPSTONE/Stage05-Disruption-Backup-Restore/manifests/
kubectl -n capstone get pods          # 5 Pods 1/1
export NODE_IP=$(hostname -I | awk '{print $1}')
cd CAPSTONE/Stage06-Service-Mesh-Latency
```

---

## L1 — Install Linkerd and viz (15 min)

**The CLI**, pinned to the version this manual was verified with:

```bash
curl -sL https://run.linkerd.io/install-edge -o /tmp/linkerd-install.sh
LINKERD2_VERSION=edge-26.9.3 sh /tmp/linkerd-install.sh
echo 'export PATH=$HOME/.linkerd2/bin:$PATH' >> ~/.bashrc
export PATH=$HOME/.linkerd2/bin:$PATH
linkerd version --client
```

**Check the cluster is ready for it.** Linkerd needs the Gateway API CRDs,
which k3s's Traefik already installed:

```bash
linkerd check --pre
```

Expected: every line `√`, ending `Status check results are √`.

**The control plane** (CRDs first, then the components):

```bash
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check
kubectl -n linkerd get pods
```

Expected: `Status check results are √`, and 3 Pods:

```
linkerd-destination-...      4/4   Running
linkerd-identity-...         2/2   Running
linkerd-proxy-injector-...   2/2   Running
```

| Component | Job |
|---|---|
| `linkerd-identity` | a certificate authority: gives every proxy a TLS identity, for automatic mTLS |
| `linkerd-destination` | tells proxies where Services' endpoints are, and their policies |
| `linkerd-proxy-injector` | an admission webhook: adds the proxy to new Pods in meshed namespaces |

**The viz extension** (metrics, Prometheus and the dashboard). The dashboard
refuses requests for host names it doesn't know, so list the one the
Ingress will use:

```bash
linkerd viz install \
  --set dashboard.enforcedHostRegexp='^(localhost|127[.]0[.]0[.]1|linkerd-viz[.]k3s[.]local)(:[0-9]+)?$' \
  | kubectl apply -f -
linkerd viz check
```

Write the regex with `[.]` and `[0-9]`, **not** `\.` and `\d`: `--set`
strips backslashes. In the reference run, a version with `\d` became `d`,
and the dashboard then refused `localhost:<port>` (and so broke
`linkerd viz dashboard`).

Expected: `Status check results are √`, and 5 Pods in `linkerd-viz`
(`metrics-api`, `prometheus`, `tap`, `tap-injector`, `web`), all `2/2`.

> **Checkpoint L1:** `linkerd check` and `linkerd viz check` are both all `√`.

## L2 — Mesh the capstone app (10 min)

Read the namespace first. The proxy annotations matter:

```bash
cat manifests/00-namespace.yaml
```

Each proxy is a **container**, so it counts against the ResourceQuota. With
no annotations, the Stage 03 LimitRange would give every proxy
200m CPU / 128Mi of limits. Six Pods would add 1200m, far past the old
`limits.cpu: 2`. The annotations size each proxy at 10m/20Mi requests and
100m/64Mi limits, and `02-resourcequota.yaml` grows `limits.cpu` to 4.

Apply, then restart the workloads. Injection only happens when a Pod is
**created**, so existing Pods have no proxy until they're replaced:

```bash
kubectl apply -f manifests/
kubectl -n capstone rollout restart statefulset/redis deploy/api deploy/web
kubectl -n capstone rollout status statefulset/redis
kubectl -n capstone rollout status deploy/api
kubectl -n capstone rollout status deploy/web
kubectl -n capstone get pods
kubectl -n capstone describe quota capstone-quota
```

Expected: every Pod is `2/2` (the app + `linkerd-proxy`), including the
new `loadgen`:

```
api-...       2/2   Running
loadgen-...   2/2   Running
redis-0       2/2   Running
web-...       2/2   Running

limits.cpu              2150m   4
limits.memory           1184Mi  2Gi
pods                    6       10
requests.cpu            320m    1
requests.memory         456Mi   1Gi
```

**Why 4 and not 3?** 2150m fits under 3. But while a rolling restart runs,
old and new Pods exist side by side. In the reference run, with the quota at
3, new api Pods were refused (`exceeded quota ... limits.cpu=600m, used:
limits.cpu=2750m, limited: limits.cpu=3`) until old ones finished
terminating. Size a quota for the rollout, not just for the steady state.

The app still works, and the counter is still there:

```bash
curl -s --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits; echo
```

(`loadgen` makes ~2 hits per second from now on, so the counter climbs fast.)

> **Checkpoint L2:** 6 Pods `2/2`, and the quota shows 2150m of 4.

## L3 — Read the latency of every hop (15 min)

Give the metrics a minute to fill, then:

```bash
linkerd viz stat deploy -n capstone
linkerd viz stat sts -n capstone
```

Expected (your numbers will differ a little):

```
NAME      MESHED   SUCCESS      RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99   TCP_CONN
api          2/2   100.00%   3.9rps           3ms          10ms          26ms          4
loadgen      1/1   100.00%   0.3rps           1ms          93ms          99ms          1
web          2/2   100.00%   4.0rps           7ms          52ms         161ms          7
```

| Column | Meaning |
|---|---|
| `SUCCESS` | share of responses that aren't 5xx |
| `LATENCY_P50` | half the requests were faster than this: the typical user |
| `LATENCY_P95` / `P99` | the slowest 5% / 1% of requests: the users who complain |

All figures are over the last minute, measured **inbound** at each
workload's proxy.

**Who talks to whom**, and is it encrypted?

```bash
linkerd viz edges deploy -n capstone
linkerd viz edges po -n capstone | grep -E 'SRC|redis'
```

```
SRC          DST       SRC_NS        DST_NS     SECURED
loadgen      web       capstone      capstone   √
web          api       capstone      capstone   √
...
api-...      redis-0   capstone      capstone   √
```

`SECURED √` = mutual TLS between the two proxies. You didn't configure a
single certificate: `linkerd-identity` issued them.

**One edge on its own:** only web's calls to the api:

```bash
linkerd viz stat deploy/web -n capstone --to deploy/api
```

**Live requests**, one line each, with their latency (Ctrl-C to stop):

```bash
linkerd viz tap deploy/api -n capstone --path /api/hits
```

```
rsp id=1:0 proxy=in  src=10.42.0.252:60378 dst=10.42.0.253:8000 tls=true :status=200 latency=13307µs
```

**The dashboard:** add `<NODE_IP>  linkerd-viz.k3s.local` to your hosts
file (next to `capstone.k3s.local`), then open **http://linkerd-viz.k3s.local/**.
Choose namespace `capstone` to see the same numbers, the topology graph,
and live calls. Check it from the terminal:

```bash
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --resolve linkerd-viz.k3s.local:80:$NODE_IP http://linkerd-viz.k3s.local/
```

> **Checkpoint L3:** you can name the p95 latency of web and of api, and
> show that web → api is mTLS-secured.

## L4 — Drill: a slow client makes everyone slow (10 min)

[drills/loadgen-slow.yaml](drills/loadgen-slow.yaml) runs 4 parallel loops
calling `/api/cpu?ms=300`. Each call burns 300 ms of CPU in an api Pod.
Record the "before" numbers, then start it:

```bash
linkerd viz stat deploy -n capstone
kubectl apply -f drills/loadgen-slow.yaml
```

Wait about a minute for the 1-minute window to fill, then:

```bash
linkerd viz stat deploy -n capstone
linkerd viz stat deploy/web -n capstone --to deploy/api
for i in 1 2 3; do curl -s -o /dev/null -w "user /api/hits: %{time_total}s\n" --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits; done
```

Expected:

```
NAME           MESHED   SUCCESS      RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99
api               2/2   100.00%   5.3rps         323ms         394ms         400ms
web               2/2   100.00%   3.9rps          12ms         158ms         363ms

web -> api        2/2   100.00%   2.7rps          13ms         188ms         275ms

user /api/hits: 0.022306s
user /api/hits: 0.126558s
user /api/hits: 0.165858s
```

Read it like an on-call engineer:
- api's **p50** jumped to ~320 ms: most requests the api now serves are the
  slow ones.
- The **web → api** edge carries only normal user traffic (`/api/hits`,
  `/api/info`), yet its p95 went from ~10 ms to ~190 ms. Users who never
  asked for slow work are waiting.
- **Why:** each api Pod runs gunicorn with **2 workers**, so it serves 2
  requests at a time. Four slow loops keep them busy, and user requests
  queue behind them. The 500m CPU limit throttles the Pod on top of that
  (Stage 04, S2):

```bash
kubectl -n capstone exec deploy/api -c api -- grep -E 'nr_periods|nr_throttled' /sys/fs/cgroup/cpu.stat
```

The fixes are more capacity (more replicas: Day 09's HPA) or isolating the
slow endpoint. The mesh's job was to **show which hop, and how much**.

Stop the drill and watch the numbers recover over the next minute:

```bash
kubectl delete -f drills/loadgen-slow.yaml
linkerd viz stat deploy -n capstone          # re-run after ~60 s
```

> **Checkpoint L4:** you can explain, with the numbers, why `/api/hits`
> got slower although nobody changed it.

## L5 — What the mesh can't see (5 min)

```bash
linkerd viz stat deploy/api -n capstone --to sts/redis
linkerd viz stat sts/redis -n capstone -o wide
```

```
No traffic found.
NAME    MESHED   ...   TCP_CONN   READ_BYTES/SEC   WRITE_BYTES/SEC
redis      1/1   ...          9          74.6B/s          866.3B/s
```

The redis protocol isn't HTTP, so Linkerd treats port 6379 as **opaque
TCP**. It still encrypts the connection (`SECURED √` in L3) and counts
connections and bytes. But it can't split the stream into requests, so
there's no per-request latency or success rate for redis. (The `RPS` shown
for redis is Prometheus scraping the proxy's own metrics.) For redis
latency you'd need redis's own metrics, e.g. `redis-cli --latency`:

```bash
kubectl -n capstone exec redis-0 -c redis -- timeout 5 redis-cli --latency
```

> **Checkpoint L5:** you can say which hops have request-level latency, and
> why redis doesn't.

---

## Troubleshooting

| Symptom | Likely cause / check |
|---|---|
| `linkerd: command not found` | `export PATH=$HOME/.linkerd2/bin:$PATH` |
| `linkerd check --pre` fails on Gateway API | the CRDs are missing: `kubectl get crd \| grep gateway.networking`. On k3s, Traefik installs them |
| Pods still `1/1` after `kubectl apply` | injection happens at Pod creation. Run the `rollout restart` in L2 |
| `exceeded quota` during the restart | the quota is still 2 or 3. `kubectl apply -f manifests/02-resourcequota.yaml` |
| `linkerd viz stat` shows `-` or `No traffic found` | wait a minute for metrics; check `loadgen` is `2/2 Running` |
| dashboard answers `It appears that you are trying to reach this service with a host of '...'. This does not match /.../` | the host isn't in `dashboard.enforcedHostRegexp`, or backslashes were stripped from it. Check with `kubectl -n linkerd-viz get deploy web -o yaml \| grep enforced-host`; re-run the `linkerd viz install` line in L1 |
| `linkerd viz top` says `open /dev/tty` | it needs an interactive terminal. Use `linkerd viz tap` |
| `kubectl exec redis-0 -- ...` hits the wrong container | name it: `-c redis` (the proxy is the other container) |

## Before you leave — keep it running

Leave Linkerd, viz and the meshed capstone installed; later stages build on
it. Next: [Stage 07](../Stage07-HPA-Scaling/LAB-MANUAL.md) (autoscaling the API). To catch
up later (after L1):

```bash
kubectl apply -f CAPSTONE/Stage06-Service-Mesh-Latency/manifests/
kubectl -n capstone rollout restart statefulset/redis deploy/api deploy/web
```

**Removing it** (only if you must; not exercised in the reference run):

```bash
kubectl apply -f CAPSTONE/Stage05-Disruption-Backup-Restore/manifests/   # quota back, loadgen stays
kubectl annotate namespace capstone linkerd.io/inject-
kubectl -n capstone delete deploy loadgen
kubectl -n capstone rollout restart statefulset/redis deploy/api deploy/web
linkerd viz uninstall | kubectl delete -f -
linkerd uninstall | kubectl delete -f -
```
