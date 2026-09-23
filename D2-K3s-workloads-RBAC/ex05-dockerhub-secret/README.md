# ex05 — store Docker Hub credentials in a Secret

A `kubernetes.io/dockerconfigjson` Secret holds registry login details. The
kubelet uses it (via `imagePullSecrets`) to authenticate when pulling images —
required for **private** images and for beating Docker Hub's anonymous
pull-rate limit.

> ✅ **Verified on the live cluster — captured output in [OUTPUT.md](OUTPUT.md).**

> Use a Docker Hub **access token** (Account Settings → Security → New Access
> Token), not your account password.

## 1. Create the Secret

### Option A — from your existing `docker login` (easiest)

```bash
docker login -u <DOCKERHUB_USERNAME>          # prompts for the access token
# writes ~/.docker/config.json

kubectl create secret generic dockerhub-creds \
  --from-file=.dockerconfigjson=$HOME/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson
```

### Option B — pass credentials directly

```bash
kubectl create secret docker-registry dockerhub-creds \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<DOCKERHUB_USERNAME> \
  --docker-password=<DOCKERHUB_ACCESS_TOKEN> \
  --docker-email=vishwanath.murthy@gmail.com
```

### Option C — from the template file

```bash
# build the base64 payload
AUTH=$(printf '%s:%s' "<USER>" "<TOKEN>" | base64 -w0)
printf '{"auths":{"https://index.docker.io/v1/":{"username":"<USER>","password":"<TOKEN>","auth":"%s"}}}' "$AUTH" | base64 -w0
# paste the result into dockerhub-secret.example.yaml, save as dockerhub-secret.yaml (gitignored), then:
kubectl apply -f dockerhub-secret.yaml
```

## 2. Inspect it

```bash
kubectl get secret dockerhub-creds
kubectl get secret dockerhub-creds -o jsonpath='{.type}' ; echo

# decode to see what's inside (base64 is encoding, NOT encryption)
kubectl get secret dockerhub-creds -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | python3 -m json.tool
```

## 3. Use it — two ways

### Per-Deployment (`imagePullSecrets:` in the pod spec) — used in `python-app.yaml`

```bash
kubectl apply -f ../ex04-configmap/configmap.yaml
kubectl apply -f ../ex04-configmap/redis.yaml
kubectl apply -f python-app.yaml
kubectl rollout status deployment/python-app
```

### Cluster-wide (attach to the ServiceAccount) — every new pod inherits it

```bash
kubectl patch serviceaccount default \
  -p '{"imagePullSecrets":[{"name":"dockerhub-creds"}]}'
# now pods don't need their own imagePullSecrets line
```

## 4. Prove authentication happened

```bash
kubectl delete pod -l app=python-app          # force a fresh pull
kubectl get events --field-selector reason=Pulled --sort-by=.lastTimestamp | tail -3
kubectl describe pod -l app=python-app | grep -A2 -i 'pull\|image'
```

To really see it fail without the secret: reference a private repo image, apply
without `imagePullSecrets`, and watch the pod go `ImagePullBackOff` with
`pull access denied`.

## Secret vs ConfigMap

| | ConfigMap | Secret |
|--|-----------|--------|
| Intended for | non-sensitive config | credentials, tokens, keys, TLS |
| Stored as | plain text | base64 (encoding only) — enable [encryption at rest](https://docs.k3s.io/security/secrets-encryption) for real protection |
| `kubectl get -o yaml` shows | the values | base64 blobs (still recoverable) |
| RBAC | often readable | lock down `get`/`list` on `secrets` |
| Types | one | `Opaque`, `dockerconfigjson`, `tls`, `basic-auth`, `service-account-token`, … |

## Other Secret uses (same object, different `type`)

```bash
# generic key/value the app reads as env or file
kubectl create secret generic app-secrets --from-literal=REDIS_PASSWORD=s3cr3t
#   consume: env.valueFrom.secretKeyRef  or  envFrom.secretRef  or  volume mount

# TLS cert for an Ingress
kubectl create secret tls web-tls --cert=tls.crt --key=tls.key
```

## Clean up

```bash
kubectl delete -f python-app.yaml
kubectl delete -f ../ex04-configmap/redis.yaml -f ../ex04-configmap/configmap.yaml
kubectl delete secret dockerhub-creds
kubectl patch serviceaccount default -p '{"imagePullSecrets":null}'   # if you set option 3b
```
