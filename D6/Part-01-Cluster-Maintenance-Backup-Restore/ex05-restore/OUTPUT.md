# ex05 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`.
Result: **PASS** — a real, complete disaster-simulation-and-restore cycle:
delete a namespace, restore the node's datastore from ex04's backup, get it
back exactly as it was.

## Step 1: simulate accidental data loss

```console
$ kubectl delete namespace canary
namespace "canary" deleted
$ kubectl get namespace canary
Error from server (NotFound): namespaces "canary" not found
```

## Step 2: restore from the ex04 backup

```console
$ bash ex05-restore/restore-datastore.sh /root/k3s-backups/k3s-server-20260913-231134.tar.gz
Stopping k3s...
Moving current state aside (not deleting) -> /var/lib/rancher/k3s/server.before-restore-1789321398
Extracting /root/k3s-backups/k3s-server-20260913-231134.tar.gz -> /var/lib/rancher/k3s/server
Starting k3s...
Waiting for the API to come back...
API back after ~2s

Restore complete. Pre-restore state kept at: /var/lib/rancher/k3s/server.before-restore-1789321398
```

The **current** (post-deletion) state is moved aside, not deleted — if the
restore turns out to be wrong, it can be put back. Only after confirming the
restore is good (next step) is that sidestep directory actually removed.

## Step 3: is the canary back?

```console
$ kubectl get namespace canary
NAME     STATUS   AGE
canary   Active   2m12s

$ kubectl get configmap canary-marker -n canary -o jsonpath='{.data}'
{"created":"2026-09-13","proof":"this-value-must-survive-a-restore"}
```

**Exactly** the data from ex04 — the same `proof` string, the same
`created` value. `AGE 2m12s` is the object's **original** creation
timestamp carried through the restore, not a new one — this is a true
point-in-time restore, not a re-creation.

## Step 4: nothing else disturbed

```console
$ kubectl get nodes
NAME         STATUS   ROLES           AGE     VERSION
lab-g2-vm2   Ready    control-plane   5d11h   v1.36.4+k3s1

$ kubectl get pods -A | wc -l
10
$ kubectl get pods -A | grep -v Running | grep -v Completed
(nothing - every Pod is Running or Completed)

$ kubectl get csidriver
NAME             ...   AGE
nfs.csi.k8s.io   ...   25h                # from Day 06, restored intact too

$ systemctl is-active nfs-kernel-server
active                                     # a systemd service, not part of k3s's own state - untouched either way
```

Everything from every earlier day (the NFS CSI driver installed in Day 06,
in this case) came back exactly as it was at backup time — the restore
operates on the **whole** datastore, not just the canary.

## Step 5: clean up, now that the restore is confirmed good

```console
$ kubectl delete namespace canary
$ sudo rm -rf /var/lib/rancher/k3s/server.before-restore-1789321398
```

## The full cycle, start to finish

1. `ex04`: create a canary → back up (`stop → tar → start`, ~2s downtime).
2. `ex05`: delete the canary → restore (`stop → swap directory → start`,
   ~2s downtime) → canary is back with its original timestamp.

Both operations are real, both were timed in single-digit seconds of API
downtime, and the "move aside, don't delete" pattern in the restore script
means a **bad** restore is itself still recoverable.
