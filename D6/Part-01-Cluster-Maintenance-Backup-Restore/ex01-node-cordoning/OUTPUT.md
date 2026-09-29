# ex01 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`.
Result: **PASS** — cordoning stopped new Pods from scheduling while leaving
every already-running Pod completely untouched.

```console
$ kubectl cordon lab-g2-vm2
node/lab-g2-vm2 cordoned

$ kubectl get node lab-g2-vm2
NAME         STATUS                     ROLES           AGE     VERSION
lab-g2-vm2   Ready,SchedulingDisabled   control-plane   5d11h   v1.36.4+k3s1
```

`SchedulingDisabled` is a separate flag from `Ready` — the node is still
healthy and serving traffic for what's already on it; it's just no longer a
candidate for new work.

```console
$ kubectl apply -f ex01-node-cordoning/test-pod.yaml
pod/cordon-test created

$ kubectl get pod cordon-test -o wide
NAME          READY   STATUS    RESTARTS   AGE   IP       NODE
cordon-test   0/1     Pending   0          3s    <none>   <none>

$ kubectl describe pod cordon-test
Warning  FailedScheduling  0/1 nodes are available: 1 node(s) were unschedulable.
```

Meanwhile, everything already running is unaffected — no restarts, no
`Terminating`, nothing:

```console
$ kubectl -n kube-system get pods | grep -E 'traefik|coredns'
coredns-54996dc9b4-ntjnk       1/1   Running   0   5d11h
traefik-59b7647586-wf58t       1/1   Running   0   5d11h
```

Uncordoning immediately makes the node schedulable again, and the Pod that
was waiting lands right away:

```console
$ kubectl uncordon lab-g2-vm2
node/lab-g2-vm2 uncordoned
$ kubectl get node lab-g2-vm2
NAME         STATUS   ROLES           AGE     VERSION
lab-g2-vm2   Ready    control-plane   5d11h   v1.36.4+k3s1

$ kubectl get pod cordon-test -o wide
NAME          READY   STATUS    RESTARTS   AGE   IP            NODE
cordon-test   1/1     Running   0          15s   10.42.0.191   lab-g2-vm2
```

## Why this matters for maintenance

Cordoning is step one of *any* planned node maintenance: mark the node
unschedulable **before** you touch it, so nothing new lands there while
you're working, without disturbing anything that's already running. `drain`
(ex02) is the next step — actually moving the existing workload off.
