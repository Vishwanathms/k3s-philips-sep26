# Capstone stage 10 — verified run

Captured **2026-09-29** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
over a healthy, running Stage 09 (restricted PSA, NetworkPolicies, redis
password). `break-capstone.sh` injects 5 faults; T1–T5 diagnose and fix
each for real, one at a time; `verify-capstone.sh` confirms recovery.
Counter climbed from 99969 (pre-break) to 112256 (post-fix) — loadgen never
stopped, proving nothing was reset. Result: **PASS** for all 5 faults.

> One genuine surprise while breaking the cluster: `break-capstone.sh`'s
> first cut of fault 4 (`resources.limits.memory: 8Mi` only, leaving
> `requests.memory: 128Mi`) was **rejected by the API server**:
> `requests: Invalid value: "128Mi": must be less than or equal to memory
> limit of 8Mi`. The script now patches both fields — a real reminder that
> `requests ≤ limits` is enforced at admission, not just a convention.

## Inject the faults

```console
$ ./scripts/break-capstone.sh
[1/5] Service/web: selector typo (app=web -> app=web-tier)
service/web patched
[2/5] Deployment/api: bad image tag
deployment.apps/api image updated
[3/5] NetworkPolicy/api: ingress port doesn't match the container's 8000
networkpolicy.networking.k8s.io/api patched
[4/5] StatefulSet/redis: memory request+limit cut from 128Mi to 8Mi
statefulset.apps/redis patched
[5/5] Deployment/web: readinessProbe path typo (/healthz -> /healthzz)
deployment.apps/web patched
```

~90 seconds later, all 5 symptoms are live at once:

```console
$ kubectl -n capstone get pods,svc,endpoints
NAME                          READY   STATUS             RESTARTS
pod/api-6d655c4644-4wrvq      1/2     Running            0
pod/api-6d655c4644-g2gng      1/2     Running            0
pod/api-8467fbbcb9-7lgqm      1/2     ImagePullBackOff   0
pod/redis-0                   1/2     CrashLoopBackOff   4 (60s ago)
pod/web-5567498448-2bcgz      2/2     Running            0
pod/web-5567498448-grcjl      2/2     Running            0
pod/web-68bdb6f566-b6vnn      1/2     Running            0

NAME              ENDPOINTS
endpoints/api                 <- empty: cascade from redis being down (below)
endpoints/redis
endpoints/web     <none>      <- empty: selector mismatch

$ curl -s -m5 -o /dev/null -w 'status=%{http_code}\n' -H 'Host: capstone.k3s.local' http://$NODE_IP/
status=503
```

Two Services have zero endpoints, one Pod never got past `ImagePullBackOff`,
one is `CrashLoopBackOff`, and the site returns 503. That's the whole
picture *before* any diagnosis — students see all 5 at once, same as a
real incident.

## T1 — Service/web selector

```console
$ kubectl -n capstone get svc web -o jsonpath='{.spec.selector}{"\n"}'
{"app":"web-tier"}
$ kubectl -n capstone get pods -l app=web --show-labels
web-...-2bcgz   2/2   Running   ...,app=web,tier=web,...
web-...-grcjl   2/2   Running   ...,app=web,tier=web,...
web-...-b6vnn   1/2   Running   ...,app=web,tier=web,...

$ kubectl -n capstone patch service web --type=merge -p '{"spec":{"selector":{"app":"web"}}}'
service/web patched
$ kubectl -n capstone get endpoints web
web   10.42.0.46:8080,10.42.0.49:8080   <- 2, not 3 (3rd Pod still 1/2)
```

## T2 — Deployment/web readinessProbe

```console
$ kubectl -n capstone describe pod web-68bdb6f566-b6vnn | grep -A1 Unhealthy
Warning  Unhealthy  (x2)   Readiness probe failed: HTTP probe failed with statuscode: 502
Warning  Unhealthy  (x21)  Readiness probe failed: HTTP probe failed with statuscode: 404
$ kubectl -n capstone get deploy web -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}{"\n"}'
/healthzz
$ kubectl -n capstone patch deployment web --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/healthz"}]'
deployment.apps/web patched
$ kubectl -n capstone rollout status deploy/web --timeout=60s
deployment "web" successfully rolled out
```

(The 502 before the 404: while T1 was still broken, the Service had no
endpoints, so the probe request itself couldn't complete cleanly for the
brand-new Pod yet — order of the two faults' effects overlapping briefly.)

## T3 — Deployment/api image tag

```console
$ kubectl -n capstone get pods -l app=api
api-6d655c4644-4wrvq   1/2   Running
api-6d655c4644-g2gng   1/2   Running
api-8467fbbcb9-7lgqm   1/2   ImagePullBackOff
$ kubectl -n capstone get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
localhost:5000/capstone-api:9.9.9-missing
$ kubectl -n capstone set image deployment/api api=localhost:5000/capstone-api:1.0.0
deployment.apps/api image updated
$ kubectl -n capstone rollout status deploy/api --timeout=60s
Waiting for deployment "api" rollout to finish: 1 old replicas are pending termination...
error: timed out waiting for the condition
```

Expected to still be stuck here — see T5.

## T4 — StatefulSet/redis memory

```console
$ kubectl -n capstone describe pod redis-0 | grep -A5 "Last State"
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
  Restart Count:  4
$ kubectl -n capstone get statefulset redis -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
{"limits":{"cpu":"100m","memory":"8Mi"},"requests":{"cpu":"100m","memory":"8Mi"}}
$ kubectl -n capstone patch statefulset redis --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"128Mi"},{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"128Mi"}]'
statefulset.apps/redis patched
$ kubectl -n capstone delete pod redis-0
pod "redis-0" deleted
$ kubectl -n capstone rollout status statefulset/redis --timeout=90s
Waiting for 1 pods to be ready...
partitioned roll out complete: 1 new pods have been updated...
```

## T5 — cascade resolves, then the NetworkPolicy

~30s after T4, without touching api again:

```console
$ kubectl -n capstone get pods
api-6d655c4644-4wrvq   2/2   Running
api-6d655c4644-g2gng   2/2   Running
redis-0                2/2   Running   0
web-5567498448-2bcgz   2/2   Running
web-5567498448-grcjl   2/2   Running
$ kubectl -n capstone rollout status deploy/api --timeout=60s
deployment "api" successfully rolled out
$ kubectl -n capstone get endpoints web api redis
web     10.42.0.46:8080,10.42.0.49:8080
api     10.42.0.45:8000,10.42.0.50:8000
redis   10.42.0.58:6379
```

The stuck rollout (T3) and the missing `endpoints/api` were both
downstream of T4, not separate bugs — fixing redis alone cleared both.

```console
$ kubectl -n capstone exec deploy/web -c web -- wget -q -T3 -O- http://api:8000/api/info
wget: server returned error: HTTP/1.1 503 Service Unavailable
$ kubectl -n capstone get networkpolicy api -o jsonpath='{.spec.ingress[0].ports}{"\n"}'
[{"port":8001,"protocol":"TCP"},{"port":4143,"protocol":"TCP"}]
$ kubectl -n capstone patch networkpolicy api --type=json -p='[{"op":"replace","path":"/spec/ingress/0/ports/0/port","value":8000}]'
networkpolicy.networking.k8s.io/api patched
$ kubectl -n capstone exec deploy/web -c web -- wget -q -T3 -O- http://api:8000/api/info
{"pod":"api-6d655c4644-g2gng","redis":"redis:6379","version":"1.0.0"}
```

## Final check

```console
$ ./scripts/verify-capstone.sh
web Service has endpoints                 OK
api rollout finished                      OK
web rollout finished                      OK
redis-0 not restarting                    OK
all api/web Pods Ready                    OK
counter reachable via Ingress             OK

== ALL CHECKS PASS - capstone is healthy

$ curl -s -H 'Host: capstone.k3s.local' http://192.168.230.103/api/hits
{"hits":112256,"pod":"api-6d655c4644-g2gng","version":"1.0.0"}
```

Counter at break time was 99969; 112256 after — loadgen (~2/s) ran the
entire ~9 minutes of diagnosis without being paused, and nothing was
restored from a backup.
