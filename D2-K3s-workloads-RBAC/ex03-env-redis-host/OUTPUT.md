# ex03 — verified run

Captured **2026-09-08**, k3s `v1.36.4+k3s1`, node `192.168.230.103`, ns `day01`.

**Result: PASS** — with `REDIS_HOST=redis-primary` the app reaches the renamed
Service and works; remove the env var and the app falls back to `redis`, which
does not resolve, and every request returns **HTTP 500
`redis.exceptions.ConnectionError: ... Name does not resolve`**.

```console
$ kubectl apply -f redis.yaml
deployment.apps/redis created
service/redis-primary created          # <- Service is "redis-primary", not "redis"
$ kubectl apply -f python-app.yaml
deployment.apps/python-app created
service/python-app created

$ kubectl rollout status deploy/python-app --timeout=120s
deployment "python-app" successfully rolled out

$ kubectl get svc
NAME            TYPE       CLUSTER-IP     PORT(S)          AGE
python-app      NodePort   10.43.158.11   8000:31275/TCP   2s
redis-primary   NodePort   10.43.58.110   6379:31902/TCP   2s

# --- the env var is in the container ---
$ kubectl exec deploy/python-app -- sh -c 'echo "REDIS_HOST=$REDIS_HOST"'
REDIS_HOST=redis-primary

$ kubectl exec deploy/python-app -- getent hosts redis-primary
10.43.58.110      redis-primary.day01.svc.cluster.local redis-primary
$ kubectl exec deploy/python-app -- getent hosts redis        ; echo "exit=$?"
exit=2                                  # <- "redis" does NOT resolve

$ curl -s http://192.168.230.103:31275/
Hello World! I have been seen 1 times.
```

## Prove the negative

Deployed the app **without** `REDIS_HOST` and hit the pod directly (bypassing
the NodePort, which can briefly return connection errors mid-rollout):

```console
$ kubectl create deployment python-app --image=vishwacloudlab/pythonapp:v4-var
$ kubectl expose deployment python-app --port=8000 --type=NodePort
$ kubectl rollout status deploy/python-app --timeout=120s
deployment "python-app" successfully rolled out

$ POD_IP=$(kubectl get pod -l app=python-app -o jsonpath='{.items[0].status.podIP}')
$ kubectl exec deploy/redis -- wget -qO- -T 15 http://$POD_IP:8000/
wget: server returned error: HTTP/1.1 500 INTERNAL SERVER ERROR

$ kubectl logs deploy/python-app --tail=20
  File "/code/app.py", line 12, in hello
    count = redis.incr('hits')
  ...
  File "/usr/local/lib/python3.9/site-packages/redis/connection.py", line 397, in connect_check_health
    raise ConnectionError(self._error_message(e))
redis.exceptions.ConnectionError: Error -2 connecting to redis:6379. Name does not resolve.
```

Put the variable back and it recovers:

```console
$ kubectl set env deploy/python-app REDIS_HOST=redis-primary
deployment.apps/python-app env updated
$ kubectl rollout status deploy/python-app --timeout=120s
deployment "python-app" successfully rolled out
$ curl -s http://192.168.230.103:31275/
Hello World! I have been seen 2 times.
```

## Note

During a `kubectl set env` / rollout, a `curl` against the **NodePort** may
briefly return `HTTP 000` (connection reset) while old and new pods swap and
kube-proxy reprograms. There is no readiness probe on this demo Deployment, so
the Service can route to a not-yet-ready pod for a second. Hitting the pod IP
directly (above) gives the clean `500`.
