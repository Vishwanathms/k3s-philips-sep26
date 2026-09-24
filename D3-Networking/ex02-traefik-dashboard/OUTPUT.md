# ex06 — verified run

Captured **2026-09-24** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
Traefik `v3.7.8` (chart `traefik-40.1.4+up40.1.0`). Result: **PASS**. The
dashboard went from `404` to `200` through a port-forward, stayed
unreachable on the node's public ports 80/443, and listed Lab 1's routers
with the correct Pod IPs.

## Step 1 — before: dashboard enabled but not routed

```console
$ kubectl -n kube-system get deploy traefik -o jsonpath='{.spec.template.spec.containers[0].args}' | tr ',' '\n' | grep -E 'dashboard|entryPoints.traefik'
"--entryPoints.traefik.address=:8080/tcp"
"--api.dashboard=true"

$ kubectl -n kube-system port-forward deploy/traefik 9000:8080 &
$ curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:9000/dashboard/
HTTP 404
$ curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:9000/api/overview
HTTP 404
```

## Step 2 — HelmChartConfig

```console
$ kubectl apply -f ex06-traefik-dashboard/traefik-dashboard.yaml
helmchartconfig.helm.cattle.io/traefik created

$ kubectl -n kube-system get jobs | grep traefik
helm-install-traefik       Complete   1/1           10s        19s
helm-install-traefik-crd   Complete   1/1           26s        16d

$ kubectl -n kube-system rollout status deploy/traefik
deployment "traefik" successfully rolled out

$ kubectl -n kube-system get ingressroute traefik-dashboard -o jsonpath='{.spec}'
{"entryPoints":["traefik"],"routes":[{"kind":"Rule","match":"PathPrefix(`/dashboard`) || PathPrefix(`/api`)","services":[{"kind":"TraefikService","name":"api@internal"}]}]}

$ kubectl -n kube-system get pods -l app.kubernetes.io/name=traefik
NAME                       READY   STATUS    RESTARTS         AGE
traefik-59b7647586-6mg9k   1/1     Running   12 (3h49m ago)   10d
```

The Traefik pod was **not** restarted (AGE is still 10d): the Helm upgrade
only added an IngressRoute, and Traefik loaded it on the fly.

## Step 3 — after

```console
$ curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:9000/dashboard/
HTTP 200
$ curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:9000/dashboard
HTTP 404                      # trailing slash is required

# still NOT exposed on the node's public entrypoints:
$ curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://192.168.230.103/dashboard/
HTTP 404
$ curl -sk -o /dev/null -w 'HTTP %{http_code}\n' https://192.168.230.103/dashboard/
HTTP 404
```

## Steps 4–5 — Lab 1 routers, seen through the API

With Lab 1 applied and `web` scaled to 3 replicas:

```console
$ curl -s http://localhost:9000/api/version
{"Version":"3.7.8","Codename":"langres","startDate":"2026-09-24T06:03:54.434408548Z"}

$ curl -s http://localhost:9000/api/http/routers | grep -o '"name":"[^"]*"'
"name":"argocd-argocd-server-argocd-k3s-local@kubernetes"
"name":"day05-ingress-hosts-api-k3s-local@kubernetes"
"name":"day05-ingress-hosts-web-k3s-local@kubernetes"
"name":"kube-system-traefik-dashboard-d012b7f875133eeab4e5@kubernetescrd"
"name":"ping@internal"
"name":"prometheus@internal"
"name":"websecure-day05-ingress-hosts-api-k3s-local@kubernetes"
"name":"websecure-day05-ingress-hosts-web-k3s-local@kubernetes"

$ curl -s http://localhost:9000/api/http/services/day05-ingress-web-80@kubernetes | grep -o '"url":"[^"]*"'
"url":"http://10.42.0.105:80"
"url":"http://10.42.0.107:80"
"url":"http://10.42.0.108:80"

$ kubectl get endpointslices -n day05-ingress -l kubernetes.io/service-name=web -o jsonpath='{.items[0].endpoints[*].addresses}'
["10.42.0.105"] ["10.42.0.107"] ["10.42.0.108"]

$ curl -s http://localhost:9000/api/overview
{"http":{"routers":{"total":8,"warnings":0,"errors":0},"services":{"total":8,"warnings":0,"errors":0},"middlewares":{"total":0,...
```

The `argocd-…` router comes from this VM's Argo CD install (Day 14). Student
VMs without Argo CD won't show it.

## Not verified here

- **Option B (SSH tunnel from a laptop).** This run was on the VM only, with
  no separate laptop available. The tunnel forwards to the same
  `localhost:9000` checked above.
- **`--address 0.0.0.0`** was not run, on purpose, because it exposes the
  dashboard on the network.
- **Cleanup (`kubectl delete -f traefik-dashboard.yaml`)** was not run,
  because the dashboard is meant to stay enabled on this cluster.
