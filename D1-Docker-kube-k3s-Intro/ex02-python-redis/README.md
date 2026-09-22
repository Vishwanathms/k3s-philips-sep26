# ex02 — Python app + Redis

> ✅ **Verified on the live cluster — captured output in [OUTPUT.md](OUTPUT.md).**

Two workloads talking to each other over a `Service`:

```
python-app  ──HTTP 8000──>  (you)
     │
     └──6379──>  redis  (ClusterIP Service "redis")
```

The app is a tiny Flask service — one route, `/`, that does `redis.incr('hits')`
and returns `Hello World! I have been seen N times.`:

```python
redis_host = os.getenv("REDIS_HOST", "redis")   # <-- the only knob
redis = Redis(host=redis_host, port=6379)
```

It defaults `REDIS_HOST` to `redis`, which is exactly the name of the Redis
`Service` — so this example needs **no** configuration. ex03 shows how to
override it.

## Apply

```bash
kubectl apply -f redis.yaml
kubectl apply -f python-app.yaml
kubectl rollout status deployment/redis
kubectl rollout status deployment/python-app
kubectl get pods -o wide
```

## Test

```bash
NP=$(kubectl get svc python-app -o jsonpath='{.spec.ports[0].nodePort}')
HOST=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

curl -s --retry 5 --retry-connrefused "http://$HOST:$NP/"
curl -s "http://$HOST:$NP/"
# Hello World! I have been seen 1 times.
# Hello World! I have been seen 2 times.   <-- counter lives in Redis
```

## Verify the app really reached Redis

```bash
# the counter the app increments
kubectl exec deploy/redis -- redis-cli GET hits
kubectl exec deploy/redis -- redis-cli MONITOR &   # live, Ctrl-C to stop

# what config did the app actually get?
kubectl exec deploy/python-app -- sh -c 'echo "REDIS_HOST=$REDIS_HOST"'
# REDIS_HOST=            <-- empty: the app falls back to its "redis" default
```

> `kubectl exec deploy/python-app -- env | grep -i redis` also shows
> `REDIS_SERVICE_HOST`, `REDIS_PORT`, etc. Those are **auto-injected by
> Kubernetes** for every Service that existed before the pod started — the app
> ignores them and uses its own `REDIS_HOST` variable.

## DNS: how "redis" resolves

```bash
kubectl exec deploy/python-app -- getent hosts redis
# same as redis.default.svc.cluster.local (default = the namespace)
```

## Clean up

```bash
kubectl delete -f python-app.yaml -f redis.yaml
```
