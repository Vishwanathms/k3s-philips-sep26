# ex07 — verified run

Captured **2026-09-24** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
Traefik `v3.7.8`, with the Lab 6 dashboard enabled. Result: **PASS**. The
nginx app served through Traefik, and every object appeared in the
dashboard API with the expected status. Used in
[Lab 6 Step 6](../ex06-traefik-dashboard/LAB-MANUAL.md#step-6--a-simple-nginx-app-to-watch-in-the-dashboard).

## Deploy and test

```console
$ kubectl apply -f ex07-nginx-dashboard-demo/nginx-demo.yaml
namespace/day03-nginx-demo created
configmap/nginx-page created
deployment.apps/nginx created
service/nginx created
middleware.traefik.io/add-demo-header created
ingress.networking.k8s.io/nginx created

$ for i in 1 2 3 4; do curl -s --resolve nginx.k3s.local:80:192.168.230.103 http://nginx.k3s.local/; done
Hello from nginx pod: nginx-5c89696f44-nttpk
Hello from nginx pod: nginx-5c89696f44-7xpcg
Hello from nginx pod: nginx-5c89696f44-nttpk
Hello from nginx pod: nginx-5c89696f44-7xpcg

$ curl -sI --resolve nginx.k3s.local:80:192.168.230.103 http://nginx.k3s.local/ | grep -i x-served
X-Served-Via: traefik-dashboard-demo

$ kubectl -n day03-nginx-demo get pods -o wide   (trimmed)
nginx-5c89696f44-7xpcg   10.42.0.109
nginx-5c89696f44-nttpk   10.42.0.110
```

## What the dashboard sees (its JSON API)

```console
$ curl -s http://localhost:9000/api/http/routers | grep -o '"name":"[^"]*nginx[^"]*"'
"name":"day03-nginx-demo-nginx-nginx-k3s-local@kubernetes"
"name":"websecure-day03-nginx-demo-nginx-nginx-k3s-local@kubernetes"

# router day03-nginx-demo-nginx-nginx-k3s-local@kubernetes
"entryPoints":["metrics","web"]
"middlewares":["day03-nginx-demo-add-demo-header@kubernetescrd"]
"service":"day03-nginx-demo-nginx-80"
"status":"enabled"

# middleware day03-nginx-demo-add-demo-header@kubernetescrd
"status":"enabled"
"type":"headers"

# service day03-nginx-demo-nginx-80@kubernetes
"url":"http://10.42.0.109:80"
"url":"http://10.42.0.110:80"
"serverStatus":{"http://10.42.0.109:80":"UP","http://10.42.0.110:80":"UP"}
```

## "Try these" experiments

```console
$ kubectl -n day03-nginx-demo scale deploy/nginx --replicas=3
"serverStatus":{"http://10.42.0.109:80":"UP","http://10.42.0.110:80":"UP","http://10.42.0.111:80":"UP"}

$ kubectl -n day03-nginx-demo annotate ingress nginx --overwrite \
    traefik.ingress.kubernetes.io/router.middlewares=day03-nginx-demo-does-not-exist@kubernetescrd
$ curl -s -o /dev/null -w 'HTTP %{http_code}\n' --resolve nginx.k3s.local:80:192.168.230.103 http://nginx.k3s.local/
HTTP 404
# router:
"error":["middleware \"day03-nginx-demo-does-not-exist@kubernetescrd\" does not exist"]
"status":"disabled"

$ kubectl apply -f ex07-nginx-dashboard-demo/nginx-demo.yaml
$ kubectl -n day03-nginx-demo get deploy nginx
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
nginx   2/2     2            2           65s
$ curl -s -o /dev/null -w 'HTTP %{http_code}\n' --resolve nginx.k3s.local:80:192.168.230.103 http://nginx.k3s.local/
HTTP 200
"status":"enabled"
```

Note: the router's entrypoints are `metrics` and `web`. An Ingress with no
`router.entrypoints` annotation gets routers on every public entrypoint of
this chart, which is also why a separate `websecure-…` router appears.

The demo was **left running** on this cluster. Remove it with
`kubectl delete namespace day03-nginx-demo`.
