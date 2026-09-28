# ex06 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
namespace `d5-health`. Result: **PASS** — three Pods, differing **only**
in their `resources:` block, landed in three different QoS classes, and the
kernel-level eviction priority backing that classification is directly
readable per Pod.

```console
$ kubectl apply -f ex06-qos-classes/pods.yaml
pod/qos-guaranteed created
pod/qos-burstable created
pod/qos-besteffort created

$ kubectl get pods -l qos-demo=true -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass,STATUS:.status.phase
NAME             QOS          STATUS
qos-besteffort   BestEffort   Running
qos-burstable    Burstable    Running
qos-guaranteed   Guaranteed   Running
```

| Pod | requests | limits | Why this class |
|---|---|---|---|
| `qos-guaranteed` | `cpu:100m, memory:64Mi` | `cpu:100m, memory:64Mi` | requests == limits for **every** resource, **every** container |
| `qos-burstable` | `cpu:50m, memory:32Mi` | `cpu:200m, memory:128Mi` | has requests/limits, but they don't match |
| `qos-besteffort` | *(none)* | *(none)* | no `resources:` at all, and no LimitRange in this namespace to fill any in |

## The eviction priority isn't a Kubernetes-level policy — it's a kernel value, set per Pod

```console
$ for p in qos-guaranteed qos-burstable qos-besteffort; do
    echo "$p: $(kubectl exec $p -n d5-health -- cat /proc/1/oom_score_adj)"
  done
qos-guaranteed: oom_score_adj=-997
qos-burstable: oom_score_adj=998
qos-besteffort: oom_score_adj=1000
```

`oom_score_adj` is a real Linux kernel value the kubelet sets on each
container's main process at creation time, based purely on its QoS class.
Lower = the kernel's OOM-killer leaves it alone longer; higher = it's the
first candidate killed when the **node** runs low on memory. This is the
actual mechanism behind "BestEffort Pods get evicted first" — not an
abstraction, a number in `/proc` you can read yourself.
