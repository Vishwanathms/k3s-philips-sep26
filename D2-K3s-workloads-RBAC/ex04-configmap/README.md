# ex04 — move REDIS_HOST into a ConfigMap

Same behaviour as ex03, but the value lives in a `ConfigMap` instead of the pod
spec. Config now changes without touching the Deployment YAML.

> ✅ **Verified on the live cluster — captured output in [OUTPUT.md](OUTPUT.md).**

## Apply

```bash
kubectl apply -f configmap.yaml
kubectl apply -f redis.yaml
kubectl apply -f python-app.yaml
kubectl rollout status deployment/python-app
```

## Verify

```bash
kubectl get configmap python-app-config -o yaml
kubectl exec deploy/python-app -- sh -c 'echo "REDIS_HOST=$REDIS_HOST"'   # redis-primary

NP=$(kubectl get svc python-app -o jsonpath='{.spec.ports[0].nodePort}')
HOST=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl -s --retry 5 --retry-connrefused "http://$HOST:$NP/"
```

## Change config without editing the Deployment

```bash
kubectl edit configmap python-app-config          # or:
kubectl patch configmap python-app-config --type merge -p '{"data":{"REDIS_HOST":"redis-primary"}}'

# env-var ConfigMaps are NOT auto-reloaded - restart the pods:
kubectl rollout restart deployment/python-app
kubectl rollout status deployment/python-app
```

## Two ways to consume a ConfigMap

### (A) key-by-key — `configMapKeyRef` (used in python-app.yaml)

```yaml
env:
  - name: REDIS_HOST
    valueFrom:
      configMapKeyRef: { name: python-app-config, key: REDIS_HOST }
```

Explicit, lets you rename the variable, fails loudly if the key is missing
(`optional: true` to allow missing).

### (B) all keys at once — `envFrom`

```yaml
envFrom:
  - configMapRef: { name: python-app-config }
```

Every key in `data:` becomes an env var with the same name. Less boilerplate;
you get whatever keys are there.

```bash
# try (B):
kubectl set env deployment/python-app --from=configmap/python-app-config
kubectl exec deploy/python-app -- env | grep -E 'REDIS_HOST|LOG_LEVEL'
```

### (C) as a file (mounted volume) — for config files, not env vars

```yaml
volumes:
  - name: cfg
    configMap: { name: python-app-config }
# containers[].volumeMounts:
  - { name: cfg, mountPath: /etc/app }
```

Mounted ConfigMaps **do** update in place (after a short kubelet sync delay).

## Create a ConfigMap imperatively

```bash
kubectl create configmap python-app-config \
  --from-literal=REDIS_HOST=redis-primary \
  --dry-run=client -o yaml > configmap.yaml
# or from a file:  --from-file=app.properties  /  --from-env-file=app.env
```

## Clean up

```bash
kubectl delete -f python-app.yaml -f redis.yaml -f configmap.yaml
```

## ConfigMap vs Secret

`ConfigMap` = non-sensitive config, stored/displayed in plain text.
Credentials, tokens, TLS keys → **Secret** (ex05).
