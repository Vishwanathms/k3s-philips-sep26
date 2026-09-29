# Capstone stage 08 — verified run

Captured **2026-09-28** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`
(4 CPU), applied over a running Stage 07 (Linkerd meshed, HPA on api).
Result: **PASS** for S1–S5.

> The first version of S5 filled the node **with redis running**, then
> deleted redis-0. redis rescheduled without preempting anything: deleting
> it had freed its own 110m. The drill now stops redis first and sizes one
> filler from the measured free CPU (`drills/fill-node.sh`).

## S1 — label + apply

```console
$ kubectl label node lab-g2-vm2 capstone/data=true
node/lab-g2-vm2 labeled
$ kubectl get nodes -L capstone/data
NAME         STATUS   ROLES           AGE   VERSION        DATA
lab-g2-vm2   Ready    control-plane   20d   v1.36.4+k3s1   true

$ kubectl apply -f manifests/
priorityclass.scheduling.k8s.io/capstone-data created
priorityclass.scheduling.k8s.io/capstone-app created
priorityclass.scheduling.k8s.io/capstone-batch created
statefulset.apps/redis configured
deployment.apps/api configured
deployment.apps/web configured
...
deployment.apps/loadgen configured

$ kubectl get priorityclass
NAME                      VALUE        GLOBAL-DEFAULT   AGE   PREEMPTIONPOLICY
capstone-app              10000        false            37s   PreemptLowerPriority
capstone-batch            -100         false            37s   Never
capstone-data             100000       false            37s   PreemptLowerPriority
system-cluster-critical   2000000000   false            20d   PreemptLowerPriority
system-node-critical      2000001000   false            20d   PreemptLowerPriority

POD                        READY   PRIORITY_CLASS   PRIORITY   NODE
api-69c945949f-bbq62       true    capstone-app     10000      lab-g2-vm2
api-69c945949f-dnzbr       true    capstone-app     10000      lab-g2-vm2
loadgen-67558c454b-mmv65   true    capstone-batch   -100       lab-g2-vm2
redis-0                    true    capstone-data    100000     lab-g2-vm2
web-54645b574d-ghp58       true    capstone-app     10000      lab-g2-vm2
web-54645b574d-r9466       true    capstone-app     10000      lab-g2-vm2
{"hits":15877,"pod":"api-69c945949f-dnzbr","version":"1.0.0"}
```

## S3 — required anti-affinity

```console
$ kubectl apply -f drills/required-anti-affinity.yaml
spread-strict-c55dc84f5-6g98g 1/1 Running lab-g2-vm2
spread-strict-c55dc84f5-tn2wq 0/1 Pending <none>
  Warning  FailedScheduling  9s    default-scheduler  0/1 nodes are available: 1 node(s) didn't match pod anti-affinity rules. no new claims to deallocate, preemption: 0/1 nodes are available: 1 node(s) didn't match pod anti-affinity rules.
$ kubectl delete -f drills/required-anti-affinity.yaml
```

## S4 — remove the node label

```console
$ kubectl label node lab-g2-vm2 capstone/data-
node/lab-g2-vm2 unlabeled
redis-0   2/2   Running   0     64s          # IgnoredDuringExecution
$ kubectl -n capstone delete pod redis-0
redis-0   0/2   Pending   0     5s
  Warning  FailedScheduling  5s    default-scheduler  0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector. no new claims to deallocate, preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
site: HTTP 504

$ kubectl label node lab-g2-vm2 capstone/data=true
pod/redis-0 condition met
redis-0   2/2   Running   0     20s
{"hits":15942,"pod":"api-69c945949f-dnzbr","version":"1.0.0"}
```

## S5 — preemption

```console
$ ./drills/fill-node.sh
[1/4] stopping redis so its own request doesn't count as free space
[2/4] measuring free CPU on lab-g2-vm2
      allocatable 4000m, requested 500m -> filler requests 3450m
[3/4] creating the filler (priority -100)
      node cpu requests now: 3950m (98%)
[4/4] starting redis (needs 110m, only 50m free)
pod/redis-0 condition met

$ kubectl -n capstone describe pod redis-0 | grep -E 'FailedScheduling|Scheduled'
  Warning  FailedScheduling  17s   default-scheduler  0/1 nodes are available: 1 Insufficient cpu.
  Normal   Scheduled         11s   default-scheduler  Successfully assigned capstone/redis-0 to lab-g2-vm2

$ kubectl get events -n capstone-filler ...
Preempted           filler-79cdbdcd8c-dm2cp   Preempted by pod 64d6df7b-1106-4f83-9e78-0d8aad437582 on node lab-g2-vm2
FailedScheduling    filler-79cdbdcd8c-n7nfm   0/1 nodes are available: 1 Insufficient cpu. no new claims to deallocate, preemption: not eligible due to preemptionPolicy=Never.

$ kubectl -n capstone-filler get pods
NAME                      READY   STATUS    RESTARTS   AGE
filler-79cdbdcd8c-n7nfm   0/1     Pending   0          19s
$ kubectl -n capstone exec redis-0 -c redis -- redis-cli GET hits
16063
$ kubectl delete namespace capstone-filler
```

HPA after S4/S5:

```console
Warning  FailedGetContainerResourceMetric  21s (x12 over 4m22s)  horizontal-pod-autoscaler  failed to get cpu utilization: did not receive metrics for targeted pods (pods might be unready)
api   Deployment/api   cpu: <unknown>/60%   2     6     2     176m
# a minute after redis was Ready again:
api   Deployment/api   cpu: 11%/60%   2     6     2     176m
```

Final state: Stage 08 running, node labelled `capstone/data=true`, all 6
capstone Pods `2/2` with their priority classes, node CPU requests back to
610m, `capstone-filler` deleted.
