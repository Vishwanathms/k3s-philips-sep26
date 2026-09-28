# Capstone stage 07 — verified run

Captured **2026-09-27** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`
(4 CPU / 12 GiB), Traefik `v3.7.8`, Docker `29.7.2`. Result: **PASS** for
Part A and Part B1–B11.

> **Two passes.** The first pass (B6–B11 below) ran with the images
> imported straight into k3s (`docker save … | sudo k3s ctr images import -`).
> The images were then pushed to a local registry (B4), the manifests were
> switched to `localhost:5000/…`, and the app was re-rolled from the
> registry with the counter intact (see "B4/B5" at the end).

## Part A — nginx warm-up

```console
$ kubectl -n capstone-warmup exec nginx-6d6d4c6489-9snrn -- rm /usr/share/nginx/html/index.html
$ kubectl -n capstone-warmup get pods
NAME                     READY   STATUS    RESTARTS   AGE
nginx-6d6d4c6489-9snrn   0/1     Running   0          12s
nginx-6d6d4c6489-wzsm5   1/1     Running   0          12s
nginx-6d6d4c6489-9snrn ready=false
nginx-6d6d4c6489-wzsm5 ready=true
  Warning  Unhealthy  ... Readiness probe failed: HTTP probe failed with statuscode: 404

$ kubectl -n capstone-warmup exec nginx-6d6d4c6489-wzsm5 -- rm /usr/share/nginx/html/healthz.html
$ kubectl -n capstone-warmup get pods
nginx-6d6d4c6489-9snrn   0/1     Running   0             35s
nginx-6d6d4c6489-wzsm5   1/1     Running   1 (14s ago)   35s
  Warning  Unhealthy  ... Liveness probe failed: HTTP probe failed with statuscode: 404
  Normal   Killing    ... Container nginx failed liveness probe, will be restarted
```

## B2/B3 — build and Docker smoke test

```console
$ docker images | grep capstone
vishwacloudlab/capstone-web   1.0.0   73.7MB
vishwacloudlab/capstone-api   1.0.0   191MB

$ curl -s localhost:18080/healthz        -> ok
$ curl -s localhost:18080/web-info       -> {"pod":"b3e6ef18bbf6","version":"1.0.0"}
$ curl -s localhost:18080/api/hits       -> {"hits":1,"pod":"0cd6741817a5","version":"1.0.0"}
$ curl -s localhost:18080/api/hits       -> {"hits":2,...}
$ docker exec api id                     -> uid=10001(app)
$ docker exec web id                     -> uid=101(nginx)

# redis stopped:
$ curl -s -w ' [%{http_code}]' localhost:18080/api/hits
{"error":"redis unavailable: Error -3 connecting to redis:6379. Temporary failure in name resolution.","pod":"0cd6741817a5"} [503]
/healthz 200
/ready 503 not ready: redis redis:6379 unreachable (...)
```

## B6 — deploy

```console
$ kubectl apply -k .
namespace/capstone created
resourcequota/capstone-quota created
service/api created
service/redis created
service/web created
limitrange/capstone-defaults created
deployment.apps/api created
deployment.apps/web created
statefulset.apps/redis created
ingress.networking.k8s.io/capstone created

$ kubectl -n capstone get pods,pvc
pod/api-64b9b68845-8vnql   1/1     Running   0          22s
pod/api-64b9b68845-rjpjr   1/1     Running   0          22s
pod/redis-0                1/1     Running   0          22s
pod/web-7df97787f5-hgm7x   1/1     Running   0          22s
pod/web-7df97787f5-v9vrd   1/1     Running   0          22s
persistentvolumeclaim/data-redis-0   Bound   pvc-4b1546a3-...   1Gi   RWO   local-path
```

## B7 — through the Ingress

```console
{"hits":1,"pod":"api-64b9b68845-rjpjr","version":"1.0.0"}
{"hits":2,"pod":"api-64b9b68845-8vnql","version":"1.0.0"}
{"hits":3,"pod":"api-64b9b68845-8vnql","version":"1.0.0"}
{"hits":4,"pod":"api-64b9b68845-rjpjr","version":"1.0.0"}
<title>k3s Capstone</title>
X-Web-Pod: web-7df97787f5-v9vrd

# Traefik API (dashboard view)
"name":"capstone-capstone-capstone-k3s-local@kubernetes"
"serverStatus":{"http://10.42.0.112:8080":"UP","http://10.42.0.114:8080":"UP"}
```

## B8 — QoS, quota, LimitRange

```console
POD                    QOS
api-64b9b68845-8vnql   Burstable
api-64b9b68845-rjpjr   Burstable
redis-0                Guaranteed
web-7df97787f5-hgm7x   Burstable
web-7df97787f5-v9vrd   Burstable

Resource                Used   Hard
limits.cpu              1500m  2
limits.memory           768Mi  2Gi
persistentvolumeclaims  1      2
pods                    5      10
requests.cpu            250m   1
requests.memory         320Mi  1Gi

# busybox Pod with no resources:
{"limits":{"cpu":"200m","memory":"128Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}  Burstable
```

## B9 — quota drill

```console
$ kubectl -n capstone scale deploy/api --replicas=4
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
api    3/4     3            3           5m44s
Error creating: pods "api-64b9b68845-rt5x7" is forbidden: exceeded quota: capstone-quota, requested: limits.cpu=500m, used: limits.cpu=2, limited: limits.cpu=2
```

## B10 — redis outage

```console
$ kubectl -n capstone scale statefulset/redis --replicas=0
NAME                   READY   STATUS    RESTARTS   AGE
api-64b9b68845-8vnql   0/1     Running   0          80s
api-64b9b68845-rjpjr   0/1     Running   0          80s
web-7df97787f5-hgm7x   1/1     Running   0          80s
web-7df97787f5-v9vrd   1/1     Running   0          80s
<head><title>502 Bad Gateway</title></head> ... [HTTP 502]
front page [HTTP 200]
10.42.0.113 ready=false
10.42.0.116 ready=false
Warning  Unhealthy  3s (x15 over 2m18s)  kubelet  spec.containers{api}: Readiness probe failed: HTTP probe failed with statuscode: 503

# from inside a web Pod, with no ready API endpoints:
wget: can't connect to remote host (10.43.139.100): Connection refused

$ kubectl -n capstone scale statefulset/redis --replicas=1
api-64b9b68845-8vnql   1/1     Running   0          2m49s
api-64b9b68845-rjpjr   1/1     Running   0          2m49s
redis-0                1/1     Running   0          15s
{"hits":7,"pod":"api-64b9b68845-8vnql","version":"1.0.0"}
```

The API Pods were never restarted (RESTARTS 0 throughout two outages).

## B11 — replace the redis Pod

```console
{"hits":5,...}                          # before
$ kubectl -n capstone delete pod redis-0
{"hits":6,"pod":"api-64b9b68845-8vnql","version":"1.0.0"}   # after: continued

$ kubectl -n capstone exec redis-0 -- ls /data /data/appendonlydir
/data:
appendonlydir
dump.rdb
/data/appendonlydir:
appendonly.aof.1.base.rdb
appendonly.aof.1.incr.aof
appendonly.aof.manifest
```

## B4/B5 — local registry (second pass, 2026-09-27)

```console
$ docker run -d --name capstone-registry --restart=always -p 127.0.0.1:5000:5000 \
    -v capstone-registry:/var/lib/registry registry:2
$ docker push localhost:5000/capstone-api:1.0.0
$ docker push localhost:5000/capstone-web:1.0.0
$ curl -s localhost:5000/v2/_catalog
{"repositories":["capstone-api","capstone-web"]}
$ curl -s localhost:5000/v2/capstone-api/tags/list
{"name":"capstone-api","tags":["1.0.0"]}

# k3s's containerd pulls over plain HTTP from localhost with NO registries.yaml
$ sudo k3s crictl pull localhost:5000/capstone-api:1.0.0
$ docker logs capstone-registry | grep containerd   (trimmed)
method=HEAD uri="/v2/capstone-api/manifests/1.0.0" useragent="containerd/v2.3.4-k3s1.36" status=200
# a never-before-seen test image pulled the same way: 6 blob GETs from containerd

$ kubectl kustomize . | grep image:
        image: localhost:5000/capstone-api:1.0.0
        image: localhost:5000/capstone-web:1.0.0
        image: redis:7-alpine
$ kubectl apply -k .
$ kubectl -n capstone get pods -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image
api-54b9596787-kvmlt   localhost:5000/capstone-api:1.0.0
api-54b9596787-p9d5f   localhost:5000/capstone-api:1.0.0
redis-0                redis:7-alpine
web-8697c555b5-zkph8   localhost:5000/capstone-web:1.0.0
web-8697c555b5-zzbbz   localhost:5000/capstone-web:1.0.0
{"hits":8,"pod":"api-54b9596787-kvmlt","version":"1.0.0"}     # counter continued
```

`redis-0` was not restarted by the switch (same revision, 0 restarts).

The `capstone` namespace was **left running** on this cluster as the
starting point for stage 08.
