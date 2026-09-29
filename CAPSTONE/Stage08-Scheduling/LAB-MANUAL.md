# Capstone stage 08 — Tell the scheduler what matters (Day 10)

## Scenario

Until now the scheduler has treated every capstone Pod the same. But they
aren't the same:
- redis holds the data, and its volume lives on **one node's disk**
- api and web serve users, and shouldn't all sit on the same node
- loadgen is background noise that should give way to everything else

In this stage you tell the scheduler these rules: node affinity for redis,
spreading preferences for api and web, and **priorities**, so that when the
node is full the important Pods win. Then you break each rule to see
exactly what it does.

## What changed since Stage 07

| File | Change |
|---|---|
| `manifests/03-priorityclasses.yaml` | **new**: `capstone-data` 100000, `capstone-app` 10000, `capstone-batch` -100 (never preempts) |
| `manifests/10-redis.yaml` | `priorityClassName: capstone-data`; **required** node affinity `capstone/data=true` |
| `manifests/20-api.yaml`, `30-web.yaml` | `priorityClassName: capstone-app`; **preferred** pod anti-affinity per node |
| `manifests/60-loadgen.yaml` | `priorityClassName: capstone-batch` |
| `drills/` | required anti-affinity, and a preemption drill (`fill-node.sh`) |

**Node step:** the node needs the label `capstone/data=true` **before** you
apply, or redis will have nowhere to go (S1).

## Learning objectives

- label a node and pin a workload to it with required node affinity
- explain `IgnoredDuringExecution`: what a rule does to Pods already running
- spread replicas with preferred pod anti-affinity, and explain why required anti-affinity fails on one node
- create PriorityClasses, and watch a high-priority Pod preempt a low-priority one
- explain `preemptionPolicy: Never`

## Before starting

Stage 07 running (or catch up with its manual):

```bash
cd ~/Documents/k3s-training/CAPSTONE/Stage08-Scheduling
export NODE_IP=$(hostname -I | awk '{print $1}')
export NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl -n capstone get pods              # 6 Pods 2/2
```

---

## S1 — Label the node, apply (10 min)

```bash
kubectl label node $NODE capstone/data=true
kubectl get nodes -L capstone/data
kubectl apply -f manifests/
kubectl -n capstone rollout status statefulset/redis
kubectl -n capstone rollout status deploy/api
kubectl -n capstone rollout status deploy/web
```

Every Pod template changed, so every workload rolls. Then:

```bash
kubectl get priorityclass
kubectl -n capstone get pods -o custom-columns=POD:.metadata.name,CLASS:.spec.priorityClassName,PRIORITY:.spec.priority,NODE:.spec.nodeName
```

Expected:

```
NAME                      VALUE        GLOBAL-DEFAULT   AGE   PREEMPTIONPOLICY
capstone-app              10000        false            37s   PreemptLowerPriority
capstone-batch            -100         false            37s   Never
capstone-data             100000       false            37s   PreemptLowerPriority
system-cluster-critical   2000000000   false            20d   PreemptLowerPriority
system-node-critical      2000001000   false            20d   PreemptLowerPriority

POD             CLASS            PRIORITY   NODE
api-...         capstone-app     10000      lab-g2-vm2
loadgen-...     capstone-batch   -100       lab-g2-vm2
redis-0         capstone-data    100000     lab-g2-vm2
web-...         capstone-app     10000      lab-g2-vm2
```

A Pod's priority is copied from its class **when the Pod is created**.
Changing a class later doesn't touch running Pods.

The kube-system classes are 20,000 times higher than `capstone-data`.
Nothing you create should ever outrank the cluster's own DNS, network and
metrics.

> **Checkpoint S1:** every capstone Pod shows its class and number, and the
> app still answers.

## S2 — Preferred anti-affinity: a wish, not a rule (5 min)

```bash
kubectl -n capstone get deploy api -o jsonpath='{.spec.template.spec.affinity}{"\n"}'
kubectl -n capstone get pods -l 'app in (api,web)' -o wide
```

Both api Pods and both web Pods are on the same node. The rule says
*prefer* different nodes (`weight: 100`). The scheduler adds that as a
score when it compares nodes, and with one node there's nothing to compare.
On a multi-node cluster the same file spreads the replicas with no change.

## S3 — Drill: required anti-affinity on one node (5 min)

[drills/required-anti-affinity.yaml](drills/required-anti-affinity.yaml)
has the same rule marked **required**, for 2 replicas:

```bash
kubectl apply -f drills/required-anti-affinity.yaml
kubectl -n capstone get pods -l app=spread-strict -o wide
kubectl -n capstone describe pod -l app=spread-strict | grep FailedScheduling
```

Expected:

```
spread-strict-...-6g98g   1/1   Running   lab-g2-vm2
spread-strict-...-tn2wq   0/1   Pending   <none>
Warning  FailedScheduling  ...  0/1 nodes are available: 1 node(s) didn't match pod anti-affinity rules. ...
```

The second replica refuses to share a node with the first, and there's no
other node. It stays Pending **forever**. This is why the capstone uses
`preferred`: `required` spreading needs at least as many nodes as replicas.

```bash
kubectl delete -f drills/required-anti-affinity.yaml
```

> **Checkpoint S3:** you can say why the 2nd Pod is Pending and what would
> fix it (another node, or `preferred`).

## S4 — Drill: take the label away (5 min)

```bash
kubectl label node $NODE capstone/data-
kubectl -n capstone get pod redis-0
```

redis is **still Running**. The rule is
`requiredDuringScheduling`**`IgnoredDuringExecution`**: it's checked only
when a Pod is placed. Now make it be placed again:

```bash
kubectl -n capstone delete pod redis-0
kubectl -n capstone get pod redis-0
kubectl -n capstone describe pod redis-0 | grep FailedScheduling
curl -s -o /dev/null -w 'site: HTTP %{http_code}\n' --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits
```

Expected:

```
redis-0   0/2   Pending   0   5s
Warning  FailedScheduling  ...  0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector. ...
site: HTTP 504
```

No node carries the label, so the data tier is down. Put it back:

```bash
kubectl label node $NODE capstone/data=true
kubectl -n capstone wait --for=condition=Ready pod/redis-0 --timeout=120s
curl -s --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits; echo
```

redis starts at once, with the counter intact.

**Why require this at all?** redis's volume is `local-path`: a directory on
this node's disk. On a multi-node cluster, a redis Pod that landed on
another node wouldn't find its data. (The local-path PV has its own node
affinity for that reason; the label makes the rule visible and deliberate.)

> **Checkpoint S4:** you can explain why removing the label didn't stop
> redis, but deleting the Pod did.

## S5 — Drill: preemption (10 min)

Fill the node so that redis has no room, and let priority decide.
[drills/fill-node.sh](drills/fill-node.sh):
1. stops redis, so its own CPU request doesn't count as free space
2. measures the node's free CPU and creates **one** filler Pod (priority
   -100) that requests all of it except 50m
3. starts redis again, which needs 110m (100m + 10m proxy) where only 50m is free

```bash
./drills/fill-node.sh
kubectl -n capstone wait --for=condition=Ready pod/redis-0 --timeout=120s
kubectl -n capstone describe pod redis-0 | grep -E 'FailedScheduling|Scheduled'
kubectl get events -n capstone-filler -o custom-columns=REASON:.reason,OBJ:.involvedObject.name,MSG:.message | grep -iE 'preempt|FailedScheduling'
kubectl -n capstone-filler get pods
kubectl -n capstone exec redis-0 -c redis -- redis-cli GET hits
```

Expected:

```
[2/4] measuring free CPU on lab-g2-vm2
      allocatable 4000m, requested 500m -> filler requests 3450m
[3/4] creating the filler (priority -100)
      node cpu requests now: 3950m (98%)
[4/4] starting redis (needs 110m, only 50m free)

Warning  FailedScheduling  17s  default-scheduler  0/1 nodes are available: 1 Insufficient cpu.
Normal   Scheduled         11s  default-scheduler  Successfully assigned capstone/redis-0 to lab-g2-vm2

Preempted          filler-...-dm2cp   Preempted by pod 64d6df7b-... on node lab-g2-vm2
FailedScheduling   filler-...-n7nfm   0/1 nodes are available: 1 Insufficient cpu. ... preemption: not eligible due to preemptionPolicy=Never.

filler-...-n7nfm   0/1   Pending   0   19s
```

Read it in order:
1. redis couldn't fit (`Insufficient cpu`).
2. The scheduler looked for **lower-priority** Pods whose removal would make
   room, found the filler (-100 < 100000), and evicted it (`Preempted`).
3. redis was scheduled 6 seconds later, with its data intact.
4. The filler's Deployment made a replacement. It can't fit either, and
   `preemptionPolicy: Never` forbids it from evicting anyone, so it waits
   in Pending.

Priority is about **scheduling** under pressure: requests, not actual CPU
use. The node was "full" at 98% of requested CPU while really almost idle.

```bash
kubectl delete namespace capstone-filler
```

**Watch the HPA afterwards:**

```bash
kubectl -n capstone describe hpa api | grep -E 'FailedGetContainerResourceMetric' | tail -1
```

During S4 and S5, while redis was down, the api Pods were NotReady (their
`/ready` pings redis), and the HPA ignores unready Pods:
`did not receive metrics for targeted pods (pods might be unready)`. It
showed `cpu: <unknown>` until redis came back. While the data tier is down,
the autoscaler can't see the api.

> **Checkpoint S5:** you can say why the filler was evicted and why its
> replacement didn't evict anything.

---

## Troubleshooting

| Symptom | Likely cause / check |
|---|---|
| redis `Pending` right after S1's apply | the node label is missing: `kubectl get nodes -L capstone/data`; `kubectl label node $NODE capstone/data=true` |
| `fill-node.sh`: filler `Pending` in step 3 | something else took CPU between measuring and creating. Delete `capstone-filler` and re-run |
| redis scheduled without preempting | there was still ≥110m free: another Pod finished in the meantime. Re-run `fill-node.sh` |
| an old `loadgen` Pod `Terminating` for ~30 s | busybox `sh` ignores SIGTERM, so it waits out the grace period. Harmless |
| HPA `cpu: <unknown>` after the drills | api Pods were NotReady while redis was down; it recovers within a minute of redis being Ready |
| `kubectl get priorityclass` doesn't show `capstone-*` | the apply failed; PriorityClasses are cluster-scoped, so you need cluster-level RBAC (fine as the lab admin) |

## Before you leave — keep it running

Keep the node label: every later stage's redis requires it. To catch up
later:

```bash
kubectl label node $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') capstone/data=true --overwrite
kubectl apply -f CAPSTONE/Stage08-Scheduling/manifests/
```
