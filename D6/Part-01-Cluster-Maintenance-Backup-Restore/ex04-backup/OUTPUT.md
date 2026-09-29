# ex04 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`.
Result: **PASS** — a real, restart-based file-level backup of the cluster's
SQLite datastore, ~2s of downtime, cluster fully healthy afterward.

## Step 1: a canary to prove the backup later

```console
$ kubectl apply -f ex04-backup/canary.yaml
namespace/canary created
configmap/canary-marker created
$ kubectl get configmap canary-marker -n canary
NAME            DATA   AGE
canary-marker   2      0s
```

## Step 2: confirm this cluster uses SQLite, not etcd

```console
$ sudo k3s etcd-snapshot save
level=fatal msg="Error: see server log for details: etcd datastore disabled"
```

`k3s etcd-snapshot` is real, but only for clusters started with embedded
etcd (`--cluster-init`, for HA). This cluster is a single server using k3s's
default **SQLite** datastore ("kine") — the `etcd-snapshot` subcommand does
not apply and says so immediately rather than silently doing nothing.

## Step 3: the real backup

```console
$ bash ex04-backup/backup-datastore.sh
Stopping k3s...
Archiving /var/lib/rancher/k3s/server -> /root/k3s-backups/k3s-server-20260913-231134.tar.gz
Starting k3s...
Waiting for the API to come back...
API back after ~2s

Backup written to: /root/k3s-backups/k3s-server-20260913-231134.tar.gz
-rw-r--r-- 1 root root 3430374 Sep 13 23:11 ...tar.gz
```

For SQLite/kine, the officially documented approach **is** a plain
file-level copy of `/var/lib/rancher/k3s/server/` (the `db/`, `tls/`, and
`token`), taken with k3s stopped so the copy is internally consistent — not
a special snapshot subcommand. Total real API downtime: ~2 seconds.

## Step 4: cluster and canary both intact afterward

```console
$ kubectl get nodes
NAME         STATUS   ROLES           AGE     VERSION
lab-g2-vm2   Ready    control-plane   5d11h   v1.36.4+k3s1

$ kubectl get configmap canary-marker -n canary -o jsonpath='{.data}'
{"created":"2026-09-13","proof":"this-value-must-survive-a-restore"}

$ kubectl get pods -A | wc -l
10
```

Nothing was lost by stopping/starting k3s for the backup — this proves the
backup **process itself** is safe. Whether the resulting `.tar.gz` is
actually a usable backup is proven separately, for real, in **ex05**: the
canary namespace gets deleted, and the restore is what brings it back.
