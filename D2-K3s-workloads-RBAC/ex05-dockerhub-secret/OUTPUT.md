# ex05 — verified run

Captured **2026-09-08**, k3s `v1.36.4+k3s1`, node `192.168.230.103`, ns `day01`.

**Result: PASS (mechanism verified)** — an unauthorized pull fails with
`pull access denied`; a `kubernetes.io/dockerconfigjson` Secret is created and
decodes to a valid `auths` document; the Deployment's `imagePullSecrets`
reference is attached to the pod; the same secret can be bound cluster-wide on
the `default` ServiceAccount.

> The creds used here are **placeholders** (`EXAMPLE_USER` / `EXAMPLE_TOKEN`) and
> the app image is public, so the successful pull did not actually exercise
> authentication (`already present on machine`). To exercise auth end-to-end,
> `docker login` with a real Docker Hub access token, rebuild the secret from
> `~/.docker/config.json`, and point the Deployment at a private repo.

## 1. Negative — no secret, unauthorized repo

```console
$ kubectl run denied --image=vishwacloudlab/python:v4-var --restart=Never
pod/denied created

$ kubectl get pod denied
NAME     READY   STATUS         RESTARTS   AGE
denied   0/1     ErrImagePull   0          13s

$ kubectl describe pod denied | sed -n '/Events:/,$p'
Events:
  Type     Reason     Age   From               Message
  ----     ------     ----  ----               -------
  Normal   Pulling    12s   kubelet            Pulling image "vishwacloudlab/python:v4-var"
  Warning  Failed     10s   kubelet            Failed to pull image "vishwacloudlab/python:v4-var": ...
                                               pull access denied, repository does not exist or may
                                               require authorization: server message: insufficient_scope:
                                               authorization failed
  Warning  Failed     10s   kubelet            Error: ErrImagePull
  Normal   BackOff    10s   kubelet            Back-off pulling image "vishwacloudlab/python:v4-var"
  Warning  Failed     10s   kubelet            Error: ImagePullBackOff
```

## 2. Create the Secret

```console
$ kubectl create secret docker-registry dockerhub-creds \
    --docker-server=https://index.docker.io/v1/ \
    --docker-username=EXAMPLE_USER \
    --docker-password=EXAMPLE_TOKEN \
    --docker-email=vishwanath.murthy@gmail.com
secret/dockerhub-creds created

$ kubectl get secret dockerhub-creds
NAME              TYPE                             DATA   AGE
dockerhub-creds   kubernetes.io/dockerconfigjson   1      1s

$ kubectl get secret dockerhub-creds -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
{"auths":{"https://index.docker.io/v1/":{"username":"EXAMPLE_USER","password":"EXAMPLE_TOKEN",
"email":"vishwanath.murthy@gmail.com","auth":"RVhBTVBMRV9VU0VSOkVYQU1QTEVfVE9LRU4="}}}
```

`auth` is just `base64("EXAMPLE_USER:EXAMPLE_TOKEN")` — base64 is **encoding, not
encryption**. Anyone with `get secret` RBAC can read it back.

## 3. Deployment uses it via `imagePullSecrets`

```console
$ kubectl apply -f ../ex04-configmap/configmap.yaml
$ kubectl apply -f ../ex04-configmap/redis.yaml
$ kubectl apply -f python-app.yaml
deployment.apps/python-app created
service/python-app created
$ kubectl rollout status deploy/python-app --timeout=120s
deployment "python-app" successfully rolled out

$ kubectl get pod -l app=python-app -o jsonpath='{.items[0].spec.imagePullSecrets}'
[{"name":"dockerhub-creds"}]

$ kubectl describe pod -l app=python-app | grep -iE 'image|pull'
    Image:      vishwacloudlab/pythonapp:v4-var
    Image ID:   docker.io/vishwacloudlab/pythonapp@sha256:259c6fd6...
  Normal  Pulled  1s  kubelet  Container image "vishwacloudlab/pythonapp:v4-var" already present on machine

$ curl -s http://192.168.230.103:31809/
Hello World! I have been seen 1 times.
```

## 4. Cluster-wide via the ServiceAccount

```console
$ kubectl patch serviceaccount default -p '{"imagePullSecrets":[{"name":"dockerhub-creds"}]}'
serviceaccount/default patched
$ kubectl get serviceaccount default -o jsonpath='{.imagePullSecrets}'
[{"name":"dockerhub-creds"}]
# every new pod in this namespace now inherits the pull secret - no per-Deployment line needed
```

## Cleanup

```console
$ kubectl delete -f python-app.yaml -f ../ex04-configmap/redis.yaml -f ../ex04-configmap/configmap.yaml
$ kubectl delete secret dockerhub-creds
$ kubectl patch serviceaccount default --type=json -p '[{"op":"remove","path":"/imagePullSecrets"}]'
serviceaccount/default patched
```
