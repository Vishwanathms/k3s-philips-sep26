# ex07 — Python + Redis: LoadBalancer, ExternalName, NetworkPolicy

Builds on [Day-01 ex02 (python-app + redis)](../../Day-01-Deployments-Config-Secrets/ex02-python-redis/)
and combines three Service/networking concepts from this module into one
scenario, in the shared `day02-networking` namespace.

> 🎓 **Students:** work through [LAB-MANUAL.md](LAB-MANUAL.md) instead of this
> file — it has step-by-step instructions with checkpoints to verify each
> concept as you go. This README is the reference/architecture summary.

```
                         LoadBalancer (03)                 ExternalName (04)
                       python-app-public:8089            python-app-alias
                                │                                │
                                ▼                                ▼
                     ┌────────────────────┐          CNAME → python-app.day02-networking
   (you, external) ─▶│  Service: python-app │◀── in-cluster clients using the alias
                     │  ClusterIP :8000     │
                     └─────────┬───────────┘
                                │ app calls redis:6379
                                ▼
                     ┌────────────────────┐
                     │  Service: redis      │
                     │  ClusterIP :6379     │
                     └─────────┬───────────┘
                                │  NetworkPolicy (05): default-deny + allow-from python-app only
                                ▼
                           redis Pod
```

The same Flask + Redis app from ex02 (`redis.incr('hits')`, defaults
`REDIS_HOST=redis`) is reused unmodified — this lab only changes how the
Services around it are exposed and secured.

| File | Concept | What it does |
|---|---|---|
| [01-redis.yaml](01-redis.yaml) | Deployment + ClusterIP Service | `redis` — backing store, internal-only |
| [02-python-app.yaml](02-python-app.yaml) | Deployment + ClusterIP Service | `python-app` — the Flask app, talks to `redis` by DNS name |
| [03-loadbalancer.yaml](03-loadbalancer.yaml) | **LoadBalancer** | `python-app-public` exposes the app externally via k3s ServiceLB on port 8089 |
| [04-externalname.yaml](04-externalname.yaml) | **ExternalName** | `python-app-alias` is a CNAME to `python-app.day02-networking.svc.cluster.local` — lets other namespaces/clients reach the app through a stable alias without knowing the real Service name |
| [05-networkpolicy.yaml](05-networkpolicy.yaml) | **NetworkPolicy** | default-deny ingress to `redis`, then allow only from Pods labeled `app: python-app` |
| [06-redis-client.yaml](06-redis-client.yaml) | test Pod | an *unapproved* client (label `access: redis-unapproved`) used to prove the NetworkPolicy blocks direct access to `redis` |

## Prerequisites

```bash
kubectl apply -f ../00-namespace.yaml   # creates day02-networking, if not already present
```

## Apply

```bash
kubectl apply -f 01-redis.yaml
kubectl apply -f 02-python-app.yaml
kubectl rollout status deployment/redis -n day02-networking
kubectl rollout status deployment/python-app -n day02-networking

kubectl apply -f 03-loadbalancer.yaml
kubectl apply -f 04-externalname.yaml
kubectl apply -f 05-networkpolicy.yaml
kubectl apply -f 06-redis-client.yaml
```

## Test 1 — LoadBalancer reaches the app externally

```bash
kubectl get svc python-app-public -n day02-networking
# k3s ServiceLB assigns a node's IP as EXTERNAL-IP

EXTIP=$(kubectl get svc python-app-public -n day02-networking -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s "http://$EXTIP:8089/"
curl -s "http://$EXTIP:8089/"
# Hello World! I have been seen 1 times.
# Hello World! I have been seen 2 times.
```

## Test 2 — ExternalName resolves to the in-cluster app

```bash
# from any pod in the cluster, e.g. the redis-client test pod
kubectl exec -n day02-networking redis-client -- getent hosts python-app-alias
# resolves via CNAME to python-app.day02-networking.svc.cluster.local -> the ClusterIP

# an app pod could use http://python-app-alias:8000/ exactly like http://python-app:8000/
```

## Test 3 — NetworkPolicy blocks direct Redis access

`python-app` (labeled `app: python-app`) is allowed; `redis-client`
(labeled `access: redis-unapproved`) is not.

```bash
# denied: redis-client is not labeled app: python-app
kubectl exec -n day02-networking redis-client -- redis-cli -h redis -p 6379 ping
# expect: connection timed out / no reply

# allowed: traffic that originates from python-app pods reaches redis normally
kubectl exec -n day02-networking deploy/python-app -- sh -c \
  'echo -e "PING\r" | timeout 3 nc redis 6379'
# expect: +PONG
```

## Clean up

```bash
kubectl delete -f 06-redis-client.yaml -f 05-networkpolicy.yaml -f 04-externalname.yaml \
  -f 03-loadbalancer.yaml -f 02-python-app.yaml -f 01-redis.yaml
```

> Note: these manifests have not yet been run against a live cluster in this
> session (no cluster was reachable). Verify by running the apply/test steps
> above, then capture results in an `OUTPUT.md` following the pattern used in
> [ex06's OUTPUT.md](../ex06-networkpolicy/OUTPUT.md).
