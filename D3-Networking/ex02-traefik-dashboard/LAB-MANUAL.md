# Lab manual — Lab 6: The Traefik dashboard

## Learning objectives

By the end of this lab, students can:

- explain why the Traefik dashboard exists on k3s but can't be reached by default
- turn it on the k3s way, with a `HelmChartConfig` that overrides the bundled Traefik chart
- open the dashboard from the VM's browser, and from their laptop through an SSH tunnel
- use the dashboard, and its JSON API, to check that Traefik picked up an Ingress, and to trace which router, service and middleware handle a request

**Duration:** ~30 minutes

---

## Background — why you can't open it yet

k3s installs Traefik as a Helm chart (`HelmChart/traefik` in `kube-system`).
The chart starts Traefik with `--api.dashboard=true`, so the dashboard is
built in, but **no route leads to it**:

| Traefik entrypoint | Container port | Published on the node? | Serves |
|---|---|---|---|
| `web` | 8000 | yes → node port **80** | your Ingresses (HTTP) |
| `websecure` | 8443 | yes → node port **443** | your Ingresses (HTTPS) |
| `traefik` | 8080 | **no** — cluster-internal only | ping, and the dashboard **once a route exists** |

The dashboard is served by an internal Traefik service called
`api@internal`. It only answers when an `IngressRoute` points at it. The
chart can create that `IngressRoute` for you, but the option is off by
default (`ingressRoute.dashboard.enabled: false`).

You don't edit the k3s HelmChart directly, because k3s rewrites it on every
restart. Instead you create a **`HelmChartConfig` with the same name**
(`traefik`). k3s merges its values into the chart and re-runs the Helm
upgrade for you. This is the supported way to customise any component
bundled with k3s.

---

## Before starting

```bash
kubectl -n kube-system get deploy traefik           # READY 1/1
kubectl -n kube-system get deploy traefik \
  -o jsonpath='{.spec.template.spec.containers[0].args}' | tr ',' '\n' | grep dashboard
# "--api.dashboard=true"
```

Run everything from the `Day-05-Ingress-Traffic-Management/` folder. You
need cluster-admin rights, because the change is made in `kube-system`.

---

## Step 1 — See that the dashboard is not reachable yet

Forward a local port to Traefik's private `traefik` entrypoint (container
port 8080):

```bash
kubectl -n kube-system port-forward deploy/traefik 9000:8080 >/dev/null 2>&1 &
sleep 3
curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:9000/dashboard/
kill %1
```

Expected: `HTTP 404`. Traefik is listening, but nothing routes to `api@internal` yet.

> **Checkpoint 1:** you got `404`, not `connection refused`. A `404` means
> the port-forward reached Traefik; only the route is missing.

---

## Step 2 — Enable the dashboard with a `HelmChartConfig`

Look at the manifest first:

```bash
cat ex06-traefik-dashboard/traefik-dashboard.yaml
```

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik            # must match the k3s HelmChart name
  namespace: kube-system   # must be kube-system
spec:
  valuesContent: |-
    ingressRoute:
      dashboard:
        enabled: true
```

Apply it and watch k3s re-run the Helm install job:

```bash
kubectl apply -f ex06-traefik-dashboard/traefik-dashboard.yaml
sleep 20
kubectl -n kube-system get jobs | grep helm-install-traefik
# helm-install-traefik   Complete   1/1   ...   <a few seconds old>
kubectl -n kube-system rollout status deploy/traefik
```

Check the `IngressRoute` the chart created:

```bash
kubectl -n kube-system get ingressroute traefik-dashboard \
  -o jsonpath='{.spec}{"\n"}'
```

Expected output (on one line):

```json
{"entryPoints":["traefik"],"routes":[{"kind":"Rule",
 "match":"PathPrefix(`/dashboard`) || PathPrefix(`/api`)",
 "services":[{"kind":"TraefikService","name":"api@internal"}]}]}
```

Look at three fields:

- `entryPoints: ["traefik"]` means the route exists **only** on the private port 8080
- `match` sends `/dashboard` (the web UI) and `/api` (the JSON the UI reads) to it
- `api@internal` is Traefik's built-in dashboard service. `@internal` means Traefik itself provides it, not a Kubernetes Service

> **Checkpoint 2:** `kubectl -n kube-system get ingressroute` lists
> `traefik-dashboard`. The Traefik pod did **not** restart (its AGE is
> unchanged). Traefik reads new routes on the fly, without a restart.

---

## Step 3 — Open the dashboard

The dashboard has **no login**. Keep it off the public network and reach it
through `kubectl port-forward`. Anyone who can run that command already has
cluster access.

### Option A — browser on the VM itself

```bash
kubectl -n kube-system port-forward deploy/traefik 9000:8080
```

Leave that terminal open and browse to:

**http://localhost:9000/dashboard/**

> The **trailing `/` is required**. `http://localhost:9000/dashboard`
> (no slash) returns `404 page not found`.

### Option B — browser on your laptop (SSH tunnel, recommended)

1. On the **VM**, start the port-forward exactly as in Option A. It
   listens on the VM's `localhost:9000` only.
2. On your **laptop**, open a second terminal and create an SSH tunnel to
   the VM. Replace `<VM-IP>` with your VM's address; get it on the VM with
   `hostname -I | awk '{print $1}'`.

   ```bash
   ssh -N -L 9000:localhost:9000 labuser@<VM-IP>
   ```

   This works as-is on Windows 10/11 PowerShell, macOS and Linux. It prints
   nothing and keeps running.
3. On your laptop, browse to **http://localhost:9000/dashboard/**

Press `Ctrl+C` in both terminals to close access.

> **Why not `--address 0.0.0.0`?** `kubectl port-forward --address 0.0.0.0 …`
> then `http://<VM-IP>:9000/dashboard/` also works, but it puts an
> unauthenticated admin UI on the network for anyone who can reach the VM.
> The SSH tunnel reaches the same page and needs your SSH login.

> **Checkpoint 3:** the dashboard loads and shows the **HTTP / TCP / UDP**
> overview panels, with counters for Routers, Services and Middlewares.

---

## Step 4 — Use the dashboard to see your Ingresses

Every `Ingress` and `IngressRoute` in the cluster becomes a Traefik
**router**. Deploy Lab 1's Ingress (skip this if it's still running):

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f ex01-basic-ingress/01-backends.yaml
kubectl apply -f ex01-basic-ingress/02-ingress.yaml
```

In the dashboard, open **HTTP → HTTP Routers** and find these:

| Router name (as shown) | Comes from | What to notice |
|---|---|---|
| `day03-ingress-hosts-web-k3s-local@kubernetes` | Lab 1 `Ingress` | provider `kubernetes` = a standard Ingress; rule `Host(\`web.k3s.local\`)` |
| `day03-ingress-hosts-api-k3s-local@kubernetes` | Lab 1 `Ingress` | one router per `host` rule |
| `websecure-day03-ingress-hosts-web-k3s-local@kubernetes` | Lab 1 `Ingress` | an Ingress with no entrypoint annotation gets a router on **both** `web` and `websecure` |
| `kube-system-traefik-dashboard-…@kubernetescrd` | Step 2 | provider `kubernetescrd` = an `IngressRoute` CRD; entrypoint `traefik` |
| `ping@internal`, `prometheus@internal` | Traefik itself | built-in routers |

Click the **web** router. The detail page shows the full path of a request:
**Entrypoint → Router (rule) → Middlewares → Service → Servers (Pod IPs)**.
Compare the server IPs with:

```bash
kubectl get endpointslices -n day03-ingress -l kubernetes.io/service-name=web \
  -o jsonpath='{.items[0].endpoints[*].addresses}{"\n"}'
```

They match. Traefik sends traffic straight to Pod IPs, not through the
Service's ClusterIP.

**Try it:** scale the backend and watch the dashboard update, with no
reload needed:

```bash
kubectl scale deployment/web -n day03-ingress --replicas=3
```

Refresh the router's service page and you should see three servers.

> **Checkpoint 4:** you can name the entrypoint, rule, service and server
> IPs for `web.k3s.local` from the dashboard alone.

---

## Step 5 — The same data from the command line (the JSON API)

The dashboard is just a web page that reads `/api`. You can read the same
data yourself, which is handy for scripts or when no browser is available.
With the port-forward still running:

```bash
curl -s http://localhost:9000/api/version; echo
# {"Version":"3.7.8","Codename":"langres",...}

curl -s http://localhost:9000/api/http/routers | grep -o '"name":"[^"]*"'
# "name":"day03-ingress-hosts-api-k3s-local@kubernetes"
# "name":"kube-system-traefik-dashboard-...@kubernetescrd"
# ...

curl -s http://localhost:9000/api/overview; echo    # the numbers on the front page
```

Useful endpoints: `/api/http/routers`, `/api/http/services`,
`/api/http/middlewares`, `/api/entrypoints`, and any of these with
`/<name>` appended for a single object.

> **Checkpoint 5:** `/api/http/routers` lists the same routers you saw in
> Step 4.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `404 page not found` at `/dashboard/` | Step 2 not applied, or the IngressRoute isn't there yet: `kubectl -n kube-system get ingressroute traefik-dashboard` |
| `404` at `/dashboard` | missing the trailing slash, use `/dashboard/` |
| Browser: "unable to connect" | the `port-forward` terminal was closed, or (Option B) the SSH tunnel isn't running |
| `unable to listen on port 9000` | the port is in use; pick another local port, e.g. `9001:8080`, and use it in the URL/tunnel |
| `helm-install-traefik` job `Failed` | bad YAML in `valuesContent`: `kubectl -n kube-system logs job/helm-install-traefik` |
| Your Ingress isn't in HTTP Routers | wrong `ingressClassName`, or the backend Service has no endpoints. Look for errors (red) on the dashboard's router list, and check `kubectl -n kube-system logs deploy/traefik --tail=50` |
| `http://<VM-IP>/dashboard/` returns 404 | expected: the dashboard is **not** on ports 80/443 by design |

---

## Cleanup

Lab 1 resources (if you deployed them only for this lab):

```bash
kubectl delete namespace day03-ingress
```

**Leave the dashboard enabled.** Later days use it for debugging. To turn
it off again:

```bash
kubectl delete -f ex06-traefik-dashboard/traefik-dashboard.yaml
```

k3s then re-runs the Traefik chart with its default values, and the
`traefik-dashboard` IngressRoute is removed.
