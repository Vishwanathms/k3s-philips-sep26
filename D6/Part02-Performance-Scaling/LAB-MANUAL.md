# Lab manual — Performance & Scaling

## Learning objectives

By the end of this lab, students can scale a Deployment both imperatively
and declaratively, configure and observe a real HPA reacting to real CPU
load (including its asymmetric scale-up/scale-down timing), install and use
a real VPA in both recommendation-only and applying modes, safely combine
HPA and VPA on one workload, and predict — then verify — how many more Pods
of a given size a node can actually schedule.

## Before starting

```bash
kubectl apply -f 00-namespace.yaml
export NS=day09-scaling
kubectl top node                              # metrics-server must be working
kubectl get crd | grep autoscaling.k8s.io      # VerticalPodAutoscaler CRDs present
```

If VPA isn't installed yet:

```bash
git clone --filter=blob:none --sparse https://github.com/kubernetes/autoscaler.git /tmp/autoscaler
cd /tmp/autoscaler && git sparse-checkout set vertical-pod-autoscaler
helm install vpa vertical-pod-autoscaler/charts/vertical-pod-autoscaler -n kube-system
kubectl -n kube-system get pods -l app.kubernetes.io/name=vertical-pod-autoscaler
```

---

## Lab 1 — Scaling applications

```bash
kubectl apply -f ex01-scaling-applications/deployment.yaml
kubectl rollout status deployment/web -n "$NS" --timeout=60s

kubectl scale deployment/web -n "$NS" --replicas=5        # imperative
kubectl get pods -l app=web -n "$NS"

kubectl patch deployment web -n "$NS" -p '{"spec":{"replicas":2}}'   # declarative
kubectl get pods -l app=web -n "$NS"
kubectl delete -f ex01-scaling-applications/deployment.yaml
```

---

## Lab 2 — Horizontal Pod Autoscaler

```bash
kubectl apply -f ex02-horizontal-pod-autoscaler/deployment.yaml
kubectl rollout status deployment/php-apache -n "$NS" --timeout=60s
kubectl apply -f ex02-horizontal-pod-autoscaler/hpa.yaml

kubectl get hpa php-apache -n "$NS"     # cpu: <unknown>/50% at first - wait ~30s
```

Generate real load and watch it scale up:

```bash
kubectl apply -f ex02-horizontal-pod-autoscaler/load-generator.yaml
watch kubectl get hpa php-apache -n "$NS"
# expect: cpu% climbs, REPLICAS climbs toward 5 within ~1 minute
```

Remove the load and watch the (much slower, by design) scale-down:

```bash
kubectl delete pod load-generator -n "$NS"
watch kubectl get hpa php-apache -n "$NS"
# cpu% drops to 0% almost immediately; REPLICAS stays at 5 for ~5 minutes
# (the default scale-down stabilization window), then drops to 1
kubectl describe hpa php-apache -n "$NS" | grep -A2 ScaleDownStabilized
```

Cleanup: `kubectl delete -f ex02-horizontal-pod-autoscaler/hpa.yaml -f ex02-horizontal-pod-autoscaler/deployment.yaml -n "$NS"`

---

## Lab 3 — Vertical Pod Autoscaler

```bash
kubectl apply -f ex03-vertical-pod-autoscaler/deployment.yaml   # requests.cpu: 10m, real usage much higher
kubectl top pod -l app=rightsize-me -n "$NS"                    # compare to the request

kubectl apply -f ex03-vertical-pod-autoscaler/vpa-off.yaml      # recommend only
sleep 90
kubectl describe vpa rightsize-me -n "$NS"                      # Target: cpu ~587m (vs. requested 10m)
```

Apply it for real — note the safety guard that fires first:

```bash
kubectl apply -f ex03-vertical-pod-autoscaler/vpa-auto.yaml     # updateMode: Recreate
kubectl -n kube-system logs -l app.kubernetes.io/component=updater --tail=5
# "Too few replicas ... livePods=1 requiredPods=2 globalMinReplicas=2"

kubectl scale deployment/rightsize-me -n "$NS" --replicas=2     # give it room to evict safely
kubectl get pods -l app=rightsize-me -n "$NS" -w                # watch one Terminate, a new one appear
kubectl get pods -l app=rightsize-me -n "$NS" \
  -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.containers[0].resources}{"\n"}{end}'
```

Cleanup: `kubectl delete deployment rightsize-me vpa rightsize-me -n "$NS"`

---

## Lab 4 — Resource optimization: combining HPA and VPA safely

```bash
kubectl apply -f ex04-resource-optimization/deployment.yaml
kubectl apply -f ex04-resource-optimization/hpa-cpu.yaml            # HPA owns CPU -> replica count
kubectl apply -f ex04-resource-optimization/vpa-memory-only.yaml    # VPA owns memory ONLY

kubectl get hpa php-apache -n "$NS"
kubectl describe vpa php-apache -n "$NS" | grep -A6 Recommendation
# the VPA recommendation has a Memory field and NO Cpu field at all
```

Cleanup: `kubectl delete deploy/php-apache svc/php-apache hpa/php-apache vpa/php-apache -n "$NS"`

---

## Lab 5 — Capacity planning

```bash
kubectl top node
kubectl describe node | grep -A6 "Allocated resources"
# compare the two - "Allocated" (requests) can be far lower than real usage

bash ex05-capacity-planning/capacity-math.sh 250 256
# predicts how many more 250m-CPU/256Mi-memory Pods fit, and which resource binds

kubectl apply -f ex05-capacity-planning/verify-prediction.yaml   # deploys MORE than predicted
kubectl get pods -l app=capacity-test -n "$NS" --no-headers | awk '{print $3}' | sort | uniq -c
# confirm the Running/Pending split matches the prediction exactly
kubectl describe pod <a Pending one> -n "$NS" | tail -3          # Insufficient cpu/memory

kubectl delete -f ex05-capacity-planning/verify-prediction.yaml
```

---

## Design exercise — Cluster Autoscaler concepts (no cluster changes)

Read [design-cluster-autoscaler-concepts.md](design-cluster-autoscaler-concepts.md)
— how Cluster Autoscaler adds/removes nodes via a provider API, and why a
single hand-provisioned VM has no node pool for it to act on.

---

## Troubleshooting sequence

```bash
kubectl get hpa,vpa -n <ns>
kubectl describe hpa <name> -n <ns>          # Conditions block explains stalls
kubectl describe vpa <name> -n <ns>          # Recommendation + Conditions
kubectl -n kube-system logs -l app.kubernetes.io/component=updater --tail=30
kubectl -n kube-system logs -l app.kubernetes.io/component=recommender --tail=30
kubectl top node; kubectl top pod -n <ns>    # needs metrics-server
```

| Symptom | Likely cause |
|---|---|
| HPA shows `cpu: <unknown>/50%` | metrics-server hasn't scraped yet - wait ~30s, or check `kubectl top pod` works at all |
| HPA won't scale up under real load | check the target's `requests.cpu` is actually set - a Pod with no CPU request has no denominator for "% of request" |
| HPA scaled up fast but takes minutes to scale down | expected - default scale-down stabilization window is 5 minutes, by design, to avoid flapping |
| VPA `Off` mode shows no recommendation | needs ~1-2 minutes of observed usage first; check the recommender Pod is `Running` |
| VPA `Recreate` mode never evicts anything | check the updater's logs for `"Too few replicas"` - it won't evict below the replica floor (default 2) |
| HPA and VPA both changing things unpredictably on one workload | they're targeting the same resource - split with `controlledResources` (`ex04`) or don't combine them on that metric |
| Capacity prediction didn't match reality | re-run `capacity-math.sh` immediately before testing - "Allocated resources" changes as other Pods come and go |

## Cleanup

```bash
kubectl delete namespace day09-scaling
```

VPA itself (`ex03`'s Helm release, in `kube-system`) is left running for
future days, same as the NFS server and CSI driver from Day 06.
