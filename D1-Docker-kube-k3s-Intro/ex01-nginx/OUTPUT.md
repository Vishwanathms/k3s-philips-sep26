# ex01 — verified run

Captured on **2026-09-08**, k3s `v1.36.4+k3s1`, node `lab-g2-vm2`
(`192.168.230.103`), namespace `day01`.

**Result: PASS** — 2/2 pods Running, Service has both endpoints, `HTTP 200` from
the NodePort, nginx welcome page served.

```console
$ kubectl apply -f nginx.yaml
deployment.apps/nginx created
service/nginx created

$ kubectl rollout status deploy/nginx --timeout=120s
Waiting for deployment "nginx" rollout to finish: 1 of 2 updated replicas are available...
deployment "nginx" successfully rolled out

$ kubectl get deploy,rs,pod,svc -l app=nginx -o wide
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES              SELECTOR
deployment.apps/nginx   2/2     2            2           3s    nginx        nginx:1.27-alpine   app=nginx

NAME                               DESIRED   CURRENT   READY   AGE
replicaset.apps/nginx-795669cc7d   2         2         2       2s

NAME                         READY   STATUS    RESTARTS   AGE   IP           NODE
pod/nginx-795669cc7d-nvmvf   1/1     Running   0          2s    10.42.0.31   lab-g2-vm2
pod/nginx-795669cc7d-qr9bw   1/1     Running   0          2s    10.42.0.30   lab-g2-vm2

NAME            TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
service/nginx   NodePort   10.43.38.134   <none>        80:31814/TCP   2s

$ curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://192.168.230.103:31814
HTTP 200

$ curl -s http://192.168.230.103:31814 | sed -n '1,7p'
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;

$ kubectl get endpoints nginx
NAME    ENDPOINTS                     AGE
nginx   10.42.0.30:80,10.42.0.31:80   2s      # <- one entry per pod

$ kubectl delete -f nginx.yaml
deployment.apps "nginx" deleted
service "nginx" deleted
```

> `Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1
> EndpointSlice` — harmless; `kubectl get endpointslices` is the modern form.
