# ex03 — REDIS_HOST as an environment variable

`vishwacloudlab/pythonapp:v4-var` reads **`REDIS_HOST`** from its environment
(falling back to `redis` if unset). This example proves it: the Redis `Service`
is renamed `redis-primary`, so the app only works when we pass the env var.

> ✅ **Verified on the live cluster — captured output in [OUTPUT.md](OUTPUT.md).**

## Apply

```bash
kubectl apply -f redis.yaml
kubectl apply -f python-app.yaml
kubectl rollout status deployment/python-app
```

## See the env var reach the container

```bash
kubectl exec deploy/python-app -- sh -c 'echo "REDIS_HOST=$REDIS_HOST"'
# REDIS_HOST=redis-primary

kubectl exec deploy/python-app -- getent hosts redis-primary   # resolves
kubectl exec deploy/python-app -- getent hosts redis           # nothing (NXDOMAIN)
```

## Test it works

```bash
NP=$(kubectl get svc python-app -o jsonpath='{.spec.ports[0].nodePort}')
HOST=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl -s --retry 5 --retry-connrefused "http://$HOST:$NP/"
# Hello World! I have been seen 1 times.
kubectl exec deploy/redis -- redis-cli GET hits
```

## Prove the negative

```bash
# remove the env var -> app falls back to "redis" -> fails
kubectl set env deployment/python-app REDIS_HOST-
kubectl rollout status deployment/python-app

# hit the POD directly (the NodePort can flap mid-rollout and return HTTP 000)
POD_IP=$(kubectl get pod -l app=python-app -o jsonpath='{.items[0].status.podIP}')
kubectl exec deploy/redis -- wget -qO- -T 15 "http://$POD_IP:8000/"
# wget: server returned error: HTTP/1.1 500 INTERNAL SERVER ERROR

kubectl logs deploy/python-app --tail=20
# redis.exceptions.ConnectionError: Error -2 connecting to redis:6379. Name does not resolve.

# put it back
kubectl set env deployment/python-app REDIS_HOST=redis-primary
kubectl rollout status deployment/python-app
```

## Other ways to set env (same result)

```bash
# imperative
kubectl set env deployment/python-app REDIS_HOST=redis-primary

# from a literal at create time
kubectl create deployment python-app --image=vishwacloudlab/pythonapp:v4-var
kubectl set env deployment/python-app REDIS_HOST=redis-primary
```

The hard-coded `value:` here is fine for one variable, but config that changes
per environment belongs in a **ConfigMap** → ex04.

## Clean up

```bash
kubectl delete -f python-app.yaml -f redis.yaml
```
