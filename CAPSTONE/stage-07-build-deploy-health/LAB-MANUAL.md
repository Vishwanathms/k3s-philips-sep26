# Capstone stage 07 — Build, deploy and keep it healthy

**Day 07: Health Management & Resource Governance** · ~2 hours

## Scenario

Your team has written a small web app: an **nginx** front end, a **python**
API, and **redis** to store a visit counter. It has never run outside a
laptop. Your job today is to package it, publish the images, and run it on
k3s so that it:

1. tells Kubernetes the truth about its health, per tier;
2. can't eat the node, and can't be starved by a noisy neighbour;
3. survives its database going away, without restarting everything; and
4. keeps its data when the database Pod is replaced.

You'll keep this app for the rest of the course. Every later day adds to it.

## Learning objectives

By the end of this stage you can:

- explain the difference between liveness and readiness, and **see** it on a live Pod
- write a Dockerfile, build an image, run a container registry, and push the image to it
- deploy a 3-tier app with Deployments, a StatefulSet, Services and an Ingress
- choose probes per tier, and explain why the API's liveness must **not** check redis
- set requests/limits, and predict each Pod's QoS class
- use a `LimitRange` and a `ResourceQuota` to budget a namespace, and read the quota error when it's exceeded

## Before starting

```bash
cd ~/Documents/k3s-training          # the course repo
docker version                       # Client AND Server lines
kubectl get nodes                    # Ready
kubectl get storageclass             # local-path (default)
kubectl get ingressclass             # traefik
```

Set two variables, because every later command uses them. `REGISTRY` is the
local container registry you'll start in step B4, on your own VM:

```bash
export REGISTRY=localhost:5000
export NODE_IP=$(hostname -I | awk '{print $1}')
```

Optional but recommended: the Traefik dashboard from
[Day 05 Lab 6](../../Day-05-Ingress-Traffic-Management/ex06-traefik-dashboard/LAB-MANUAL.md),
so you can watch Pods join and leave the load balancer.

---

# Part A — The concept, on plain nginx (20 min)

Before the real app, see what each probe does on something simple. The
manifest [part-a-nginx/nginx-warmup.yaml](part-a-nginx/nginx-warmup.yaml)
runs 2 nginx replicas with two probes:

| Probe | Checks | Fails when | What Kubernetes does |
|---|---|---|---|
| readiness | `GET /index.html` | the file is deleted | removes the Pod from the Service. **No restart.** |
| liveness | `GET /healthz.html` | the file is deleted | **kills and restarts** the container |

```bash
kubectl apply -f CAPSTONE/stage-07-build-deploy-health/part-a-nginx/nginx-warmup.yaml
kubectl -n capstone-warmup rollout status deploy/nginx
kubectl -n capstone-warmup get pods
```

### A1 — Break readiness

```bash
P=$(kubectl -n capstone-warmup get pod -l app=nginx -o jsonpath='{.items[0].metadata.name}')
kubectl -n capstone-warmup exec $P -- rm /usr/share/nginx/html/index.html
sleep 5
kubectl -n capstone-warmup get pods
kubectl -n capstone-warmup get endpointslices -l kubernetes.io/service-name=nginx \
  -o jsonpath='{range .items[0].endpoints[*]}{.targetRef.name} ready={.conditions.ready}{"\n"}{end}'
kubectl -n capstone-warmup describe pod $P | grep 'probe failed'
```

Expected:

```
nginx-6d6d4c6489-9snrn   0/1     Running   0          12s     <- NOT ready, RESTARTS 0
nginx-6d6d4c6489-wzsm5   1/1     Running   0          12s
nginx-6d6d4c6489-9snrn ready=false
nginx-6d6d4c6489-wzsm5 ready=true
Readiness probe failed: HTTP probe failed with statuscode: 404
```

> **Checkpoint A1:** the broken Pod is `0/1` with **0 restarts**, and its
> endpoint is `ready=false`. The Service sends all traffic to the other Pod.

### A2 — Break liveness

```bash
Q=$(kubectl -n capstone-warmup get pod -l app=nginx -o jsonpath='{.items[1].metadata.name}')
kubectl -n capstone-warmup exec $Q -- rm /usr/share/nginx/html/healthz.html
sleep 20
kubectl -n capstone-warmup get pods
kubectl -n capstone-warmup describe pod $Q | grep -E 'Liveness probe failed|Killing'
```

Expected:

```
nginx-6d6d4c6489-wzsm5   1/1     Running   1 (14s ago)   35s     <- restarted once
Liveness probe failed: HTTP probe failed with statuscode: 404
Container nginx failed liveness probe, will be restarted
```

The restart **fixed** it, because the container starts from a clean filesystem
that recreates `healthz.html`. That's the only case where liveness helps:
**when restarting the process actually cures the problem.**

> **Checkpoint A2:** you can explain why deleting `index.html` caused no
> restart, but deleting `healthz.html` did.

Fix A1 and clean up:

```bash
kubectl -n capstone-warmup exec $P -- sh -c 'echo hi > /usr/share/nginx/html/index.html'
kubectl delete namespace capstone-warmup
```

---

# Part B — The capstone app

## B1 — Read the app before you build it (10 min)

```
CAPSTONE/app/
  api/  app.py  requirements.txt  Dockerfile
  web/  default.conf.template  html/index.html  Dockerfile
```

Open [app/api/app.py](../app/api/app.py) and find the two health routes:

```python
@app.get("/healthz")        # liveness: is the process alive?  Never touches redis.
def healthz():
    return "ok\n", 200

@app.get("/ready")          # readiness: can I serve traffic?  Pings redis.
def ready():
    try:
        redis.ping()
    except RedisError as exc:
        return f"not ready: ...", 503
    return "ready\n", 200
```

**Why two routes?** If redis goes down and liveness checked redis, Kubernetes
would restart **every** API Pod over and over. That doesn't fix redis, and it
adds a restart storm on top of the outage. Readiness is the right tool: the
API Pods stop getting traffic until redis is back.

Then open [app/web/default.conf.template](../app/web/default.conf.template):
nginx serves the page, answers `/healthz` itself, and proxies `/api/` to
`${API_UPSTREAM}` (default `api:8000`, the API Service).

Both Dockerfiles run as **non-root** (`USER 10001`, and the
`nginx-unprivileged` base image on port 8080). Day 11 will require that.

## B2 — Build the images (10 min)

```bash
docker build -t $REGISTRY/capstone-api:1.0.0 CAPSTONE/app/api
docker build -t $REGISTRY/capstone-web:1.0.0 CAPSTONE/app/web
docker images | grep capstone
```

Expected (sizes approximate):

```
localhost:5000/capstone-web   1.0.0   ...   73.7MB
localhost:5000/capstone-api   1.0.0   ...   191MB
```

The image name **includes the registry** (`localhost:5000/`). That prefix
is how `docker push` knows where to send it, and how k3s knows where to
pull it from. An image with no prefix (`redis:7-alpine`) means Docker Hub.

## B3 — Smoke-test with plain Docker (10 min)

Prove the images work **before** Kubernetes is involved, so a later problem is
clearly a Kubernetes problem:

```bash
docker network create capnet
docker run -d --rm --name redis --network capnet redis:7-alpine
docker run -d --rm --name api   --network capnet $REGISTRY/capstone-api:1.0.0
docker run -d --rm --name web   --network capnet -p 18080:8080 $REGISTRY/capstone-web:1.0.0
sleep 4
curl -s localhost:18080/api/hits
curl -s localhost:18080/api/hits
```

Expected: `{"hits":1,...}`, then `{"hits":2,...}`. The container names match
the Service names the app uses in Kubernetes (`redis`, `api`), which is why
no configuration is needed.

Stop redis and check the two health routes:

```bash
docker stop redis
docker exec api python -c "
import urllib.request as u,urllib.error as e
for p in ('/healthz','/ready'):
  try: print(p, u.urlopen('http://localhost:8000'+p).status)
  except e.HTTPError as x: print(p, x.code)"
```

Expected: `/healthz 200` and `/ready 503`. The process is alive but not ready.

```bash
docker stop api web && docker network rm capnet
```

> **Checkpoint B3:** you've seen with your own eyes that `/healthz` and
> `/ready` disagree when redis is down.

## B4 — Run a local registry and push to it (10 min)

A **container registry** is just an HTTP server that stores images. Docker
Hub is one; Harbor (Day 13) is another. Here you run the official
`registry:2` image on your own VM:

```bash
docker run -d --name capstone-registry --restart=always \
  -p 127.0.0.1:5000:5000 \
  -v capstone-registry:/var/lib/registry \
  registry:2
```

| Flag | Why |
|---|---|
| `-p 127.0.0.1:5000:5000` | listen on **this VM only**. The registry has no login, so it isn't published on the network |
| `-v capstone-registry:/var/lib/registry` | images are kept in a Docker volume, so they survive the container being recreated |
| `--restart=always` | comes back after a VM reboot |

Push both images and ask the registry what it holds:

```bash
docker push $REGISTRY/capstone-api:1.0.0
docker push $REGISTRY/capstone-web:1.0.0
curl -s http://$REGISTRY/v2/_catalog
curl -s http://$REGISTRY/v2/capstone-api/tags/list
```

Expected:

```
{"repositories":["capstone-api","capstone-web"]}
{"name":"capstone-api","tags":["1.0.0"]}
```

**Can k3s pull from it?** k3s runs its own container runtime (containerd),
separate from Docker. Normally containerd refuses a registry that isn't
HTTPS, but it makes an exception for `localhost`, so **no k3s configuration
is needed**. Prove it by pulling with k3s's own tool:

```bash
sudo k3s crictl pull $REGISTRY/capstone-api:1.0.0
docker logs capstone-registry 2>&1 | grep containerd | grep -o 'uri="[^"]*manifests[^"]*"' | tail -1
```

Expected: the pull succeeds, and the registry log shows a request from
`containerd` for `/v2/capstone-api/manifests/1.0.0`.

> **Checkpoint B4:** `_catalog` lists both images, and the registry log
> shows k3s's containerd fetching one.

> **Only on this VM.** A registry on `127.0.0.1` can't be reached by other
> VMs, which is right for a single-node lab. A multi-node cluster needs a
> registry every node can reach, such as Harbor with TLS (Day 13).

## B5 — Check where the manifests pull from (2 min)

All manifests are in [manifests/](manifests/). The Deployments only say
`image: capstone-api` / `capstone-web`. The registry and tag are set in
**one place**, `kustomization.yaml`, and already point at the local registry:

```bash
cd CAPSTONE/stage-07-build-deploy-health/manifests
grep -A2 'name: capstone' kustomization.yaml
kubectl kustomize . | grep 'image:'
```

Expected:

```
        image: localhost:5000/capstone-api:1.0.0
        image: localhost:5000/capstone-web:1.0.0
        image: redis:7-alpine
```

To use a different registry later (Docker Hub, Harbor), change only the two
`newName:` lines, for example `newName: <dockerhub-user>/capstone-api`.

| File | Creates |
|---|---|
| `00-namespace.yaml` | namespace `capstone` |
| `01-limitrange.yaml` | default + max resources for any container in the namespace |
| `02-resourcequota.yaml` | the namespace's total budget |
| `10-redis.yaml` | headless Service + StatefulSet with a 1Gi PVC |
| `20-api.yaml` | API Deployment (2) + Service `api:8000` |
| `30-web.yaml` | web Deployment (2) + Service `web:80` |
| `40-ingress.yaml` | Traefik Ingress `capstone.k3s.local` → `web` |

## B6 — Deploy (10 min)

```bash
kubectl apply -k .
kubectl -n capstone rollout status statefulset/redis
kubectl -n capstone rollout status deploy/api
kubectl -n capstone rollout status deploy/web
kubectl -n capstone get pods,svc,ingress,pvc
```

Expected: 5 Pods `1/1 Running` (`redis-0`, 2 × `api-…`, 2 × `web-…`), and the
PVC `data-redis-0` `Bound`.

## B7 — Use it (5 min)

```bash
for i in 1 2 3 4; do
  curl -s --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits; echo
done
```

Expected: the count goes up, and the `pod` alternates between the two API
Pods (Service load balancing):

```
{"hits":1,"pod":"api-64b9b68845-rjpjr","version":"1.0.0"}
{"hits":2,"pod":"api-64b9b68845-8vnql","version":"1.0.0"}
...
```

**In a browser:** add `<NODE_IP>  capstone.k3s.local` to your hosts file
(`/etc/hosts`, or `C:\Windows\System32\drivers\etc\hosts` as Administrator)
and open **http://capstone.k3s.local/**. The page shows the counter and
which web Pod and API Pod served you. Click **Refresh**.

> **Checkpoint B7:** the page loads, and the counter goes up on every refresh.

## B8 — Read the resource governance you just deployed (10 min)

```bash
kubectl -n capstone get pods -o custom-columns=POD:.metadata.name,QOS:.status.qosClass
kubectl -n capstone describe quota capstone-quota
```

Expected:

```
POD                    QOS
api-...                Burstable
redis-0                Guaranteed     <- requests == limits
web-...                Burstable

Resource                Used   Hard
limits.cpu              1500m  2
limits.memory           768Mi  2Gi
persistentvolumeclaims  1      2
pods                    5      10
requests.cpu            250m   1
requests.memory         320Mi  1Gi
```

**Why is redis Guaranteed?** When the node runs short of memory, the kubelet
evicts BestEffort Pods first, then Burstable, and Guaranteed last. The data
tier is the last thing you want killed.

Now see what the `LimitRange` does to a Pod that sets **no** resources:

```bash
kubectl -n capstone run no-limits --image=busybox:1.36 --restart=Never -- sleep 30
kubectl -n capstone get pod no-limits -o jsonpath='{.spec.containers[0].resources}{"  "}{.status.qosClass}{"\n"}'
kubectl -n capstone delete pod no-limits --now
```

Expected: `{"limits":{"cpu":"200m","memory":"128Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}  Burstable`.
The defaults were filled in at admission, so nothing in this namespace can
run as BestEffort.

> **Checkpoint B8:** you can say, without looking, why each Pod has the QoS
> class it has.

## B9 — Drill: hit the quota (5 min)

Each API Pod has a 500m CPU **limit**. The quota allows 2 CPUs of limits in
total, and 1500m is already used. Predict how many API Pods you'll get from:

```bash
kubectl -n capstone scale deploy/api --replicas=4
sleep 15                          # give the 3rd Pod time to become Ready
kubectl -n capstone get deploy api
kubectl -n capstone get events --field-selector reason=FailedCreate -o custom-columns=MSG:.message | tail -1
```

Expected:

```
NAME   READY   UP-TO-DATE   AVAILABLE
api    3/4     3            3
Error creating: pods "api-..." is forbidden: exceeded quota: capstone-quota,
  requested: limits.cpu=500m, used: limits.cpu=2, limited: limits.cpu=2
```

The quota is enforced **when the Pod is created**: the 4th Pod is never
created, so it isn't `Pending`. The Deployment keeps retrying and shows
`3/4` for as long as the quota blocks it.

```bash
kubectl -n capstone scale deploy/api --replicas=2
```

> **Checkpoint B9:** you predicted 3 before running it.

## B10 — Drill: the database goes away (10 min)

Open the Traefik dashboard or the web page, then take redis away:

```bash
kubectl -n capstone scale statefulset/redis --replicas=0
sleep 15
kubectl -n capstone get pods
curl -s -w ' [HTTP %{http_code}]\n' --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits
curl -s -o /dev/null -w 'front page [HTTP %{http_code}]\n' --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/
kubectl -n capstone describe pod -l app=api | grep 'Readiness probe failed' | tail -1
```

Expected:

```
api-...   0/1   Running   0     <- both API Pods NOT ready, RESTARTS still 0
api-...   0/1   Running   0
web-...   1/1   Running   0     <- the web tier is unaffected
web-...   1/1   Running   0
... 502 Bad Gateway ... [HTTP 502]      <- nginx has no ready API to proxy to
front page [HTTP 200]                   <- but the site itself is up
Readiness probe failed: HTTP probe failed with statuscode: 503
```

Every layer behaved correctly:

| Tier | What happened | Why |
|---|---|---|
| api | NotReady, **not restarted** | `/ready` → 503; `/healthz` → still 200 |
| web | still Ready, page loads | its probes only check nginx itself |
| Traefik | still routes to both web Pods | web's readiness never failed |

Bring redis back:

```bash
kubectl -n capstone scale statefulset/redis --replicas=1
kubectl -n capstone rollout status statefulset/redis
sleep 10
kubectl -n capstone get pods
curl -s --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits; echo
```

Expected: all Pods are `1/1` again with **0 restarts**, and the counter
**continues where it left off**.

> **Checkpoint B10:** you can explain what would have happened if the API's
> **liveness** probe had called `/ready`. *(Answer: every API Pod would be
> restarted every ~30 s for the whole outage.)*

## B11 — Drill: replace the database Pod (5 min)

```bash
curl -s --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits; echo   # note N
kubectl -n capstone delete pod redis-0
kubectl -n capstone wait --for=condition=Ready pod/redis-0 --timeout=90s
sleep 8
curl -s --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits; echo   # N+1
kubectl -n capstone exec redis-0 -- ls /data /data/appendonlydir
```

The new `redis-0` reattached the **same PVC** (`data-redis-0`). The counter
was persisted to `/data` by redis's append-only file, so nothing was lost.

> **Checkpoint B11:** the counter after the delete is exactly one more than
> before it.

---

## Troubleshooting

| Symptom | Likely cause / check |
|---|---|
| `ErrImagePull` / `ImagePullBackOff` | image name doesn't match what you pushed. Compare `kubectl kustomize . \| grep image:` with `curl -s http://localhost:5000/v2/_catalog`, and read `kubectl -n capstone describe pod <pod>` |
| `connection refused` to `localhost:5000` in pod events | the registry container isn't running: `docker ps \| grep capstone-registry`; `docker start capstone-registry` |
| API Pods `0/1`, never Ready | redis isn't Ready: `kubectl -n capstone get pod redis-0`; `kubectl -n capstone logs deploy/api` |
| `redis-0` `Pending` | PVC not bound: `kubectl -n capstone get pvc`, `kubectl get sc` (need `local-path`) |
| page loads, counter shows "API error" | `curl .../api/hits` directly; `kubectl -n capstone logs deploy/web` for proxy errors |
| `404` from the browser | the browser isn't sending `capstone.k3s.local`: check the hosts file entry |
| `forbidden: exceeded quota` on a normal apply | something else is using the budget: `kubectl -n capstone describe quota` |
| `forbidden: maximum cpu usage per Container is 1` | a container asked for more than the LimitRange `max` |

## Before you leave — keep it running

**Don't delete the `capstone` namespace.** Day 08 starts from exactly this
state and will back it up and restore it. If you need to catch up later:

```bash
kubectl apply -k CAPSTONE/stage-07-build-deploy-health/manifests/
```
