# Lab manual — ex07: Python + Redis combined scenario

Builds on [Day-01 ex02](../../Day-01-Deployments-Config-Secrets/ex02-python-redis/):
the same Flask + Redis app, now exposed and secured with three Service/networking
concepts together. Read [README.md](README.md) first for the architecture diagram
and file list.

## Learning objectives

By the end of this lab, students can:
- Expose an application externally on k3s with a `LoadBalancer` Service and
  reach it from outside the cluster.
- Create a DNS alias for an existing Service with `ExternalName` and explain
  when to use it instead of renaming a Service.
- Lock a backend down with `NetworkPolicy` so only an approved application
  Pod can reach it, and prove both the allow and the deny case.

## Before starting

```bash
kubectl get nodes
kubectl apply -f ../00-namespace.yaml
export NS=d03-networking
cd Day-03-Services-Networking/ex07-python-redis-services
```

✅ **Checkpoint 0 — namespace ready**
```bash
kubectl get namespace "$NS"
# STATUS should be Active
```

## Step 1 — Deploy the app and Redis (baseline, from ex02)

```bash
kubectl apply -f 01-redis.yaml
kubectl apply -f 02-python-app.yaml
kubectl rollout status deployment/redis -n "$NS" --timeout=120s
kubectl rollout status deployment/python-app -n "$NS" --timeout=120s
```

✅ **Checkpoint 1 — both Deployments are Running with ready endpoints**
```bash
kubectl get pods -n "$NS" -l 'app in (redis,python-app)'
kubectl get endpointslice -n "$NS" -l 'kubernetes.io/service-name in (redis,python-app)'
# Expect: 1/1 Running for each pod, and each EndpointSlice lists one address
```

Sanity check the app can already reach Redis internally, from inside the
cluster, before any of the new Services are added:

```bash
kubectl run tmp-curl --rm -it --restart=Never -n "$NS" --image=busybox:1.36 \
  -- wget -T 3 -qO- http://python-app:8000/
# Hello World! I have been seen 1 times.
```

## Step 2 — Expose the app externally with LoadBalancer

k3s ships a built-in `ServiceLB` controller: it does not provision a real
cloud load balancer, but it assigns a node's IP as `EXTERNAL-IP` and forwards
the port through a `svclb-*` Pod — good enough to demonstrate the Service
type without any cloud account.

```bash
kubectl apply -f 03-loadbalancer.yaml
kubectl get service python-app-public -n "$NS" -w
# Ctrl-C once EXTERNAL-IP is no longer <pending>
```

✅ **Checkpoint 2 — LoadBalancer has an external IP and serves traffic**
```bash
EXTIP=$(kubectl get svc python-app-public -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "EXTIP=$EXTIP"
curl -s "http://$EXTIP:8089/"
curl -s "http://$EXTIP:8089/"
# Expect two lines, hit counter increasing: "... seen 1 times." then "... seen 2 times."
```

If `EXTERNAL-IP` stays `<pending>`, see [Troubleshooting](#troubleshooting).

## Step 3 — Add a DNS alias with ExternalName

`python-app-alias` is a separate Service that resolves (via CNAME) to the
real `python-app` Service. This is useful when a consumer expects a
different, stable name (e.g. `payments-alias` while the real Service is
`payments-v2`) without touching the original Service or its selector.

```bash
kubectl apply -f 04-externalname.yaml
kubectl get service python-app-alias -n "$NS"
# TYPE=ExternalName, no CLUSTER-IP, EXTERNAL-IP shows the CNAME target
```

✅ **Checkpoint 3 — the alias resolves and serves the same app**
```bash
kubectl run tmp-dns --rm -it --restart=Never -n "$NS" --image=busybox:1.36 \
  -- sh -c 'nslookup python-app-alias && wget -T 3 -qO- http://python-app-alias:8000/'
# nslookup shows a CNAME to python-app.d03-networking.svc.cluster.local
# wget returns the same "Hello World! I have been seen N times." response
```

## Step 4 — Lock Redis down with NetworkPolicy

First prove the *unapproved* client can reach Redis with no policy in place
(this is the "before" state — do not skip it, it is what makes the "after"
result meaningful):

```bash
kubectl apply -f 06-redis-client.yaml
kubectl wait --for=condition=Ready pod/redis-client -n "$NS" --timeout=60s

kubectl exec -n "$NS" redis-client -- redis-cli -h redis -p 6379 ping
# Expect: PONG   <-- unrestricted access, before the policy
```

✅ **Checkpoint 4a — before the policy, the unapproved client can reach Redis**
```bash
kubectl exec -n "$NS" redis-client -- redis-cli -h redis -p 6379 ping
# PONG
```

Now apply the default-deny + allow-from-python-app policies:

```bash
kubectl apply -f 05-networkpolicy.yaml
kubectl get networkpolicy -n "$NS"
```

✅ **Checkpoint 4b — after the policy, the unapproved client is blocked**
```bash
kubectl exec -n "$NS" redis-client -- redis-cli -h redis -p 6379 --timeout 3 ping
# Expect: a timeout / connection error (no PONG) — redis-client is labeled
# access: redis-unapproved, which the policy does not allow
```

✅ **Checkpoint 4c — the approved app (python-app) still works after the policy**
```bash
kubectl exec -n "$NS" deploy/python-app -- sh -c 'echo -e "PING\r" | timeout 3 nc redis 6379'
# +PONG

# and the app's own hit counter still increments end-to-end:
curl -s "http://$EXTIP:8089/"
# Hello World! I have been seen N times.   (N increased again)
```

## Recap — map each checkpoint to the concept it proves

| Checkpoint | Service type / feature | Proves |
|---|---|---|
| 2 | `LoadBalancer` | An external client (outside the cluster) reaches the app via a node IP + allocated port. |
| 3 | `ExternalName` | A second, stable DNS name resolves via CNAME to the real Service, with no separate selector or endpoints. |
| 4a | (none yet) | Without a NetworkPolicy, any Pod in the namespace can reach `redis` — the baseline risk. |
| 4b | `NetworkPolicy` (deny) | Default-deny ingress blocks a Pod that isn't explicitly allowed. |
| 4c | `NetworkPolicy` (allow) | The allow rule for `app: python-app` keeps the real application working — isolation, not an outage. |

## Troubleshooting

```bash
kubectl get service,endpointslice -n "$NS"
kubectl get pods -n "$NS" --show-labels
kubectl get events -n "$NS" --sort-by=.lastTimestamp | tail -20
kubectl describe service python-app-public -n "$NS"
kubectl describe networkpolicy -n "$NS"
```

| Symptom | Likely cause | Check / fix |
|---|---|---|
| `python-app-public` EXTERNAL-IP stuck `<pending>` | ServiceLB disabled or port 8089 already in use on the node | `kubectl get daemonset -n kube-system \| grep svclb`; pick a different port if occupied |
| `curl` to EXTIP times out | node firewall/security group blocks the port | Confirm the port is open on the node's network path |
| `python-app-alias` nslookup fails | ExternalName typo, or queried from outside the cluster (CNAME only resolves inside cluster DNS) | Re-check `spec.externalName`; test from a Pod, not your laptop |
| Checkpoint 4a fails (PONG expected but blocked) | policy from step 4 already applied, or a stray older policy present | `kubectl get networkpolicy -n "$NS"` and delete anything unexpected before re-testing baseline |
| Checkpoint 4b fails (still gets PONG after policy) | pod-selector label mismatch, or CNI has no policy enforcement | `kubectl get pods -n "$NS" --show-labels`; confirm k3s network-policy controller is running (`journalctl -u k3s \| grep -i "network policy controller"`) |
| Checkpoint 4c fails (python-app now blocked too) | allow rule's `podSelector` doesn't match `python-app`'s actual labels, or wrong port | `kubectl describe networkpolicy redis-allow-python-app -n "$NS"` and compare to `kubectl get pod -n "$NS" -l app=python-app --show-labels` |

## Cleanup

```bash
kubectl delete -f 06-redis-client.yaml -f 05-networkpolicy.yaml -f 04-externalname.yaml \
  -f 03-loadbalancer.yaml -f 02-python-app.yaml -f 01-redis.yaml
unset NS EXTIP
```

Or remove everything in the shared namespace at once:

```bash
kubectl delete namespace "$NS"
```
