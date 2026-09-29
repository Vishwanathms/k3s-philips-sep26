# ex02 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`.
Result: **PASS** — real, accurate `kubectl drain` planning output, with
`--dry-run=client` so nothing was actually evicted (deliberate: this is the
only node this course has; a real drain would take down Traefik, CoreDNS,
the CSI controller, and more, with nowhere else to reschedule to).

## Plain `drain` refuses, for two good reasons

```console
$ kubectl drain lab-g2-vm2 --dry-run=client
node/lab-g2-vm2 cordoned (dry run)
error: unable to drain node "lab-g2-vm2" due to error:
  [cannot delete Pods with local storage (use --delete-emptydir-data to override):
     kube-system/csi-nfs-controller-65b4f9877-fwv2j,
     kube-system/metrics-server-6dc596dfb8-fnbcx,
     kube-system/traefik-59b7647586-wf58t,
   cannot delete DaemonSet-managed Pods (use --ignore-daemonsets to ignore):
     kube-system/csi-nfs-node-gb6ss,
     kube-system/svclb-traefik-60f322a0-v6gnn]
```

`drain` refuses by default rather than silently doing something surprising:
Pods using `emptyDir` would lose that data if evicted (needs an explicit
`--delete-emptydir-data` acknowledgment), and DaemonSet Pods are meant to run
on **every** node — evicting one just means the DaemonSet controller
recreates it right back on the same node, so `drain` skips them entirely
with `--ignore-daemonsets` rather than fight that loop.

## With the flags a real maintenance drain needs

```console
$ kubectl drain lab-g2-vm2 --ignore-daemonsets --delete-emptydir-data --dry-run=client
node/lab-g2-vm2 cordoned (dry run)
Warning: ignoring DaemonSet-managed Pods: kube-system/csi-nfs-node-gb6ss, kube-system/svclb-traefik-60f322a0-v6gnn
evicting pod kube-system/coredns-54996dc9b4-ntjnk (dry run)
evicting pod kube-system/csi-nfs-controller-65b4f9877-fwv2j (dry run)
evicting pod kube-system/helm-install-traefik-crd-kdrn8 (dry run)
evicting pod kube-system/helm-install-traefik-p8cv2 (dry run)
evicting pod kube-system/local-path-provisioner-77b9867795-ks6kv (dry run)
evicting pod kube-system/metrics-server-6dc596dfb8-fnbcx (dry run)
evicting pod kube-system/traefik-59b7647586-wf58t (dry run)
node/lab-g2-vm2 drained (dry run)
```

Every `(dry run)` tag is real — nothing above actually happened:

```console
$ kubectl get node lab-g2-vm2
NAME         STATUS   ROLES           AGE     VERSION
lab-g2-vm2   Ready    control-plane   5d11h   v1.36.4+k3s1     # NOT cordoned

$ kubectl get pods -A | wc -l
10                                                              # nothing evicted
```

## What this proves about single-node maintenance

Look at the eviction list: **CoreDNS, the CSI controller, the local-path
provisioner, Traefik, metrics-server** — essentially every non-DaemonSet
system component this course depends on. On a real multi-node cluster,
`drain` moves this workload to other nodes and the cluster keeps functioning
throughout. On this one-node cluster, a real (non-dry-run) drain would leave
every one of those Pending until `uncordon` — DNS, ingress, dynamic
provisioning, and metrics would all be down for the maintenance window. That
gap is *the* reason production clusters run more than one node, and it's why
this lab stops at `--dry-run=client` rather than draining for real.
