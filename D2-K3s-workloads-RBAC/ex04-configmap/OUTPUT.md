# ex04 — verified run

Captured **2026-09-08**, k3s `v1.36.4+k3s1`, node `192.168.230.103`, ns `day01`.

**Result: PASS** — `REDIS_HOST` is delivered from the ConfigMap via
`configMapKeyRef`; patching the ConfigMap + `rollout restart` picks up changes;
`kubectl set env --from=configmap/...` (the `envFrom` equivalent) imports every
key, so `LOG_LEVEL` also appears.

```console
$ kubectl apply -f configmap.yaml
configmap/python-app-config created
$ kubectl apply -f redis.yaml
deployment.apps/redis created
service/redis-primary created
$ kubectl apply -f python-app.yaml
deployment.apps/python-app created
service/python-app created

$ kubectl rollout status deploy/python-app --timeout=120s
deployment "python-app" successfully rolled out

$ kubectl get configmap python-app-config -o yaml
apiVersion: v1
data:
  REDIS_HOST: redis-primary
kind: ConfigMap
metadata:
  name: python-app-config
  namespace: day01

# --- value arrived as an env var ---
$ kubectl exec deploy/python-app -- sh -c 'echo "REDIS_HOST=$REDIS_HOST"'
REDIS_HOST=redis-primary

$ curl -s http://192.168.230.103:31997/
Hello World! I have been seen 1 times.

# --- change the ConfigMap, then restart to pick it up ---
$ kubectl patch configmap python-app-config --type merge \
    -p '{"data":{"REDIS_HOST":"redis-primary","LOG_LEVEL":"debug"}}'
configmap/python-app-config patched
$ kubectl rollout restart deploy/python-app
deployment.apps/python-app restarted
$ kubectl rollout status deploy/python-app --timeout=120s
deployment "python-app" successfully rolled out
$ kubectl exec deploy/python-app -- sh -c 'echo "REDIS_HOST=$REDIS_HOST"'
REDIS_HOST=redis-primary

# --- envFrom style: import ALL keys ---
$ kubectl set env deploy/python-app --from=configmap/python-app-config
deployment.apps/python-app env updated
$ kubectl rollout status deploy/python-app --timeout=120s
deployment "python-app" successfully rolled out
$ kubectl exec deploy/python-app -- sh -c 'echo "REDIS_HOST=$REDIS_HOST  LOG_LEVEL=$LOG_LEVEL"'
REDIS_HOST=redis-primary  LOG_LEVEL=debug        # <- LOG_LEVEL came along too

$ curl -s http://192.168.230.103:31997/
Hello World! I have been seen 2 times.

$ kubectl delete -f python-app.yaml -f redis.yaml -f configmap.yaml
deployment.apps "python-app" deleted
service "python-app" deleted
deployment.apps "redis" deleted
service "redis-primary" deleted
configmap "python-app-config" deleted
```

## Note

Env vars sourced from a ConfigMap are read **only at container start**. Editing
the ConfigMap does **not** restart pods — you must `kubectl rollout restart`
(shown above). ConfigMaps mounted as *files* do update in place after a short
kubelet sync delay.
