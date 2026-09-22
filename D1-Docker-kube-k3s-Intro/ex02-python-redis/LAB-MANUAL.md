# Lab 02 — Multi-Service App: Python + Redis on k3s

## Objective

By the end of this lab, you will be able to:

- Deploy two separate workloads that need to talk to each other inside the cluster.
- Understand how in-cluster Service discovery (DNS) lets one Pod find another without hardcoded IPs.
- Use a `ClusterIP`-style Service reached via `NodePort` for both the internal hop (app → redis) and the external hop (you → app).
- Verify that traffic actually crossed from one Pod to another, not just that both Pods are "Running".
- Inspect environment variables Kubernetes auto-injects for Services, and see why this app ignores them.
- Clean up a multi-resource application in one command.

## Prerequisites

- Access to a running k3s cluster (single node or multi-node).
- `kubectl` configured to talk to the cluster.
- Completion of [Lab 01 — nginx](../ex01-nginx/LAB-MANUAL.md) is recommended but not required.

Verify your cluster access before starting:

```bash
kubectl get nodes
```

You should see at least one node in `Ready` state.

## Background

| Concept | What it means here |
|---|---|
| **Two Deployments** | `redis` and `python-app` are independent Deployments, each with its own Pod template, scaled and restarted independently. |
| **Service DNS** | Every Service gets a DNS name of the form `<service>.<namespace>.svc.cluster.local`, and the short form `<service>` resolves it inside the same namespace. Pods never need to know each other's IPs. |
| **App-level config vs. auto-injected env vars** | Kubernetes automatically injects `<SERVICE>_SERVICE_HOST` / `<SERVICE>_PORT` env vars into a Pod for every Service that existed *before* the Pod started. This app ignores those and instead reads its own `REDIS_HOST` variable, which defaults to `redis` — matching the Service name below on purpose. |
| **NodePort on both Services** | `python-app`'s NodePort is the one you'll actually use from outside. `redis`'s NodePort is exposed too (so you *could* reach it with `redis-cli` from the host), but the app itself always talks to Redis via the stable in-cluster name `redis:6379`, never the NodePort. |

> Why does this "just work" with zero configuration? The Redis Service is named `redis`, and the app image's built-in default is `REDIS_HOST=redis`. Service name and app default happen to match, so no environment variable needs to be set. A later exercise (ex03) shows how to override `REDIS_HOST` explicitly when that isn't the case.

## Step 1 — Review the manifests

Open [redis.yaml](redis.yaml) and [python-app.yaml](python-app.yaml) before applying anything. Identify:

1. Which Service name the Python app depends on, and where that dependency is *not* visible in the app's YAML.
2. Why `redis`'s Service is `NodePort` instead of the more common in-cluster-only `ClusterIP`.
3. Which port the app listens on internally, and how it's exposed externally.

<details>
<summary>Answer key</summary>

1. The app's Deployment ([python-app.yaml](python-app.yaml)) sets **no** `REDIS_HOST` env var at all — the dependency on a Service named `redis` is baked into the container image's default, not visible anywhere in this YAML. You'd only find it by reading the image's source or docs.
2. `NodePort` here is a deliberate lab choice so you can also query Redis directly from the host with `redis-cli -h <node-ip> -p <nodePort>` for verification. In a real environment you would use `ClusterIP` (the default) so Redis is reachable only from inside the cluster, never from outside.
3. `containerPort: 8000` on the Pod; the `python-app` Service listens on `port: 8000` and is reachable externally via its auto-assigned `nodePort` in the `30000-32767` range.

</details>

## Step 2 — Apply both manifests

Order matters here only in spirit, not enforcement: apply Redis first since the app depends on it, though Kubernetes doesn't block the app from starting before Redis is ready (it would just fail to connect until Redis comes up).

```bash
kubectl apply -f redis.yaml
kubectl apply -f python-app.yaml
kubectl rollout status deployment/redis
kubectl rollout status deployment/python-app
```

Wait for `successfully rolled out` on both before continuing.

## Step 3 — Confirm both Pods are running

```bash
kubectl get pod,svc -o wide
```

Expected: two pods (`redis-...`, `python-app-...`), both `STATUS Running`, `READY 1/1`. Note their distinct pod IPs — the app never uses these directly, it uses the `redis` Service name instead.

## Step 4 — Reach the app from outside the cluster

```bash
NP=$(kubectl get svc python-app -o jsonpath='{.spec.ports[0].nodePort}')
HOST=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "http://$HOST:$NP"

curl -s --retry 5 --retry-connrefused "http://$HOST:$NP/"
curl -s "http://$HOST:$NP/"
```

Expected output — the counter increments on every request:

```
Hello World! I have been seen 1 times.
Hello World! I have been seen 2 times.
```

If the counter were *not* incrementing across requests, that would tell you the app isn't actually persisting state in Redis (e.g. falling back to in-memory storage, or failing to connect silently).

## Step 5 — Prove the app really reached Redis

It's not enough that curl returned `200` — confirm the counter lives in Redis, not just in the app's memory:

```bash
kubectl exec deploy/redis -- redis-cli GET hits
```

This should match the number from your last curl response. Optionally watch traffic live while you curl again from another terminal:

```bash
kubectl exec deploy/redis -- redis-cli MONITOR &   # Ctrl-C to stop
curl -s "http://$HOST:$NP/" >/dev/null
```

You should see an `incr hits` command appear in the MONITOR output the instant you curl.

## Step 6 — Inspect configuration and DNS resolution

Check what the app's `REDIS_HOST` variable actually contains at runtime:

```bash
kubectl exec deploy/python-app -- sh -c 'echo "REDIS_HOST=${REDIS_HOST:-<unset>}"'
```

Expected: `REDIS_HOST=<unset>` — the app relies entirely on its built-in default.

Now look at what Kubernetes injected automatically anyway:

```bash
kubectl exec deploy/python-app -- env | grep -i redis
```

You'll see `REDIS_SERVICE_HOST`, `REDIS_PORT`, etc. — auto-injected by Kubernetes for any Service that existed before this Pod started. The app ignores these entirely; it only reads its own `REDIS_HOST` variable.

Finally, resolve the Service name the way the app does:

```bash
kubectl exec deploy/python-app -- getent hosts redis
```

Expected: the `redis` Service's **ClusterIP**, followed by `redis.<namespace>.svc.cluster.local redis` — not a Pod IP. This is the key insight: the app always talks to a stable virtual IP that Kubernetes load-balances to whichever Pod(s) currently back the `redis` Service.

## Step 7 — Clean up

```bash
kubectl delete -f python-app.yaml -f redis.yaml
```

Confirm everything is gone:

```bash
kubectl get deploy,svc -l 'app in (redis,python-app)'
```

Should return `No resources found`.

## Checkpoint questions

1. If you scale `redis` to 0 replicas while `python-app` keeps running, what happens the next time you curl the app, and why?
2. Why does `getent hosts redis` return a ClusterIP rather than a Pod IP, and why does that matter for reliability?
3. If you renamed the Redis Service from `redis` to `redis-cache` in [redis.yaml](redis.yaml), what would break, and how would you fix it without changing the container image?

<details>
<summary>Answers</summary>

1. The request would hang or fail with a connection error: `kube-proxy` still forwards to the `redis` Service, but the Service now has zero matching Pod endpoints (`kubectl get endpoints redis` would show `<none>`), so there's nowhere to route the connection.
2. DNS resolves to the Service's stable ClusterIP, not any individual Pod's IP, because Pod IPs are ephemeral — a Pod can be rescheduled and get a new IP at any time. The app only ever needs to know one thing that never changes: the Service name. `kube-proxy` handles routing that stable IP to whichever Pod(s) are currently healthy.
3. The app would keep trying to connect to a host named `redis`, which would no longer resolve to anything (`getent hosts redis` would fail), so every request would error out trying to reach Redis. Fix without touching the image: set the `REDIS_HOST=redis-cache` environment variable in `python-app.yaml`'s container spec — the app already reads this variable and only falls back to `redis` when it's unset.

</details>

## Reference: verified run

A full captured run of this exact lab (commands + output) is available in [OUTPUT.md](OUTPUT.md) for comparison against your own results.
