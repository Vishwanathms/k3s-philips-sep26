# ex02 — verified run

Captured **2026-09-08**, k3s `v1.36.4+k3s1`, node `192.168.230.103`, ns `day01`.

**Result: PASS** — app and Redis both Running; `REDIS_HOST` is unset so the app
uses its built-in default `redis`, which resolves to the Redis Service; the hit
counter increments in Redis on every request.

```console
$ kubectl apply -f redis.yaml
deployment.apps/redis created
service/redis created
$ kubectl apply -f python-app.yaml
deployment.apps/python-app created
service/python-app created

$ kubectl rollout status deploy/redis --timeout=120s
deployment "redis" successfully rolled out
$ kubectl rollout status deploy/python-app --timeout=120s
deployment "python-app" successfully rolled out

$ kubectl get pod,svc -o wide
NAME                              READY   STATUS    RESTARTS   AGE   IP           NODE
pod/python-app-844b6446cc-vp926   1/1     Running   0          2s    10.42.0.33   lab-g2-vm2
pod/redis-5b7b8cc566-dx2bw        1/1     Running   0          2s    10.42.0.32   lab-g2-vm2

NAME                 TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
service/python-app   NodePort   10.43.186.239   <none>        8000:30901/TCP   3s
service/redis        NodePort   10.43.98.115    <none>        6379:31000/TCP   3s

# --- app config: REDIS_HOST is NOT set, app falls back to "redis" ---
$ kubectl exec deploy/python-app -- sh -c 'echo "REDIS_HOST=${REDIS_HOST:-<unset>}"'
REDIS_HOST=<unset>

$ kubectl exec deploy/python-app -- getent hosts redis
10.43.98.115      redis.day01.svc.cluster.local redis

# --- hit the app 3x (NodePort 30901) ---
$ curl -s http://192.168.230.103:30901/
Hello World! I have been seen 1 times.
$ curl -s http://192.168.230.103:30901/
Hello World! I have been seen 2 times.
$ curl -s http://192.168.230.103:30901/
Hello World! I have been seen 3 times.

# --- counter is really in Redis ---
$ kubectl exec deploy/redis -- redis-cli GET hits
3

$ kubectl logs deploy/python-app --tail=4
 * Debugger PIN: 851-865-499
10.42.0.1 - - [08/Sep/2026 06:55:38] "GET / HTTP/1.1" 200 -
10.42.0.1 - - [08/Sep/2026 06:55:39] "GET / HTTP/1.1" 200 -
10.42.0.1 - - [08/Sep/2026 06:55:39] "GET / HTTP/1.1" 200 -

$ kubectl delete -f python-app.yaml -f redis.yaml
deployment.apps "python-app" deleted
service "python-app" deleted
deployment.apps "redis" deleted
service "redis" deleted
```

## Notes

- **Redis Service is `NodePort`** (per request). From the host you could also do
  `redis-cli -h 192.168.230.103 -p 31000 GET hits`. `redis-cli` was not
  installed on this box, so that line was skipped — the in-cluster
  `kubectl exec deploy/redis -- redis-cli` check covers the same thing.
  Exposing an unauthenticated Redis on a NodePort is lab-only.
- `getent hosts redis` returning the **Service ClusterIP** (not a pod IP) is
  correct — that is how a ClusterIP/NodePort Service works.
