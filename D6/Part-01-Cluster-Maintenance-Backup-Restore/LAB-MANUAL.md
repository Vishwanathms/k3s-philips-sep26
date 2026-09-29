# Lab manual — Cluster Maintenance, Backup & Restore

## Learning objectives

By the end of this lab, students can safely take a node out of scheduling
for maintenance, explain what a real drain would evict and why it refuses
by default, rotate cluster certificates without an outage, and back up and
restore a k3s cluster's entire state — and can say, precisely, how long
each of those operations actually takes because they measured it.

## Before starting

```bash
kubectl get nodes
sudo k3s certificate check | tail -5      # current cert expiry
sudo ls /var/lib/rancher/k3s/server/db    # confirms SQLite, not etcd
```

---

## Lab 1 — Node cordoning

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl cordon "$NODE"
kubectl get node "$NODE"                  # Ready,SchedulingDisabled

kubectl apply -f ex01-node-cordoning/test-pod.yaml
kubectl get pod cordon-test -o wide       # Pending
kubectl describe pod cordon-test | tail -3   # FailedScheduling: node(s) were unschedulable

kubectl -n kube-system get pods | grep -E 'traefik|coredns'   # untouched, still Running

kubectl uncordon "$NODE"
kubectl get pod cordon-test -o wide       # now Running
kubectl delete pod cordon-test --now
```

---

## Lab 2 — Node drain (dry-run only — see README.md for why)

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

kubectl drain "$NODE" --dry-run=client
# refuses: local storage + DaemonSet pods need explicit flags

kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --dry-run=client
# shows exactly what a REAL drain would evict - safely, nothing happens

kubectl get node "$NODE"                  # still Ready, NOT cordoned
kubectl get pods -A | wc -l               # nothing evicted
```

> Do not drop `--dry-run=client` on this cluster unless you're prepared for
> Traefik/CoreDNS/the CSI controller/local-path-provisioner/metrics-server
> to go `Pending` until you `uncordon` — there's no second node for them to
> land on.

---

## Lab 3 — Certificate rotation (executed for real)

```bash
sudo cat /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt \
  | openssl x509 -noout -serial -dates          # BEFORE

sudo k3s certificate rotate                     # writes new certs, backs up the old ones

sudo systemctl restart k3s
kubectl get nodes                               # poll until it answers again (~seconds)

sudo cat /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt \
  | openssl x509 -noout -serial -dates          # AFTER - different serial, new dates

sudo ls /var/lib/rancher/k3s/server/ | grep tls  # tls/ AND a tls-<timestamp>/ backup
kubectl get pods -n kube-system                 # everything back Running
```

---

## Lab 4 — Backup (executed for real)

```bash
kubectl apply -f ex04-backup/canary.yaml
kubectl get configmap canary-marker -n canary

sudo k3s etcd-snapshot save                     # fails: "etcd datastore disabled" - this is SQLite

bash ex04-backup/backup-datastore.sh /root/k3s-backups
# stops k3s, tars /var/lib/rancher/k3s/server, restarts k3s (~seconds downtime)

kubectl get nodes                               # healthy
kubectl get configmap canary-marker -n canary   # still there - backup process itself was safe
```

---

## Lab 5 — Restore (executed for real)

```bash
kubectl delete namespace canary                 # simulate accidental loss
kubectl get namespace canary                    # NotFound

BACKUP=$(sudo ls -t /root/k3s-backups/*.tar.gz | head -1)
bash ex05-restore/restore-datastore.sh "$BACKUP"
# stops k3s, moves the CURRENT state dir aside (doesn't delete it),
# extracts the backup in its place, restarts k3s

kubectl get namespace canary                    # back - Active
kubectl get configmap canary-marker -n canary -o jsonpath='{.data}'
# {"created":"2026-09-13","proof":"this-value-must-survive-a-restore"}

kubectl get pods -A                             # everything else intact too

# once you've confirmed the restore is good:
kubectl delete namespace canary
sudo rm -rf /var/lib/rancher/k3s/server.before-restore-*
```

---

## Lab 6 — Disaster recovery runbook (reference, not a run)

Read [ex06-disaster-recovery/DR-RUNBOOK.md](ex06-disaster-recovery/DR-RUNBOOK.md)
— it ties Labs 1–5 together with what actually needs a human vs. what
self-heals, real RTO numbers from the labs above, and a cron line for
scheduling Lab 4's backup script (not installed by this lab — a recurring
root cron job would outlive the training session).

---

## Design exercise — upgrade strategy (rehearsed, not executed)

Read [design-upgrade-strategy.md](design-upgrade-strategy.md) — the real
`INSTALL_K3S_VERSION` upgrade procedure, why it wasn't run live on this
cluster, and why rollback here means "restore from a pre-upgrade backup,"
not "downgrade the binary."

---

## Troubleshooting sequence

```bash
kubectl get nodes                              # SchedulingDisabled stuck? uncordon
sudo systemctl status k3s                      # is it even running?
sudo journalctl -u k3s -n 100 --no-pager        # why did a restart not come back?
sudo k3s certificate check                     # cert expiry issues
sudo ls -la /var/lib/rancher/k3s/server/       # confirm db/, tls/, token all present
```

| Symptom | Likely cause |
|---|---|
| Node stuck `SchedulingDisabled` after "finishing" maintenance | forgot `kubectl uncordon` |
| `drain` refuses immediately | missing `--ignore-daemonsets` and/or `--delete-emptydir-data` — read which Pods it's actually objecting to |
| API doesn't come back after `systemctl restart k3s` | check `journalctl -u k3s` — often a bad `/etc/rancher/k3s/config.yaml` or a port conflict, not the restart itself |
| `k3s etcd-snapshot` fails with "etcd datastore disabled" | expected on a single server with the default SQLite datastore — use file-level backup instead |
| Restore "succeeded" but nothing changed | confirm you restored the **server** directory, not just `db/`, and that k3s was actually stopped first (a live SQLite file mid-write copy is not consistent) |
| Restored cluster missing recent work | that's the RPO gap — the backup is only as fresh as when it was taken |

## Cleanup

```bash
kubectl delete namespace canary --ignore-not-found
kubectl get node                                # confirm Ready, not cordoned
```

The datastore backup at `/root/k3s-backups/*.tar.gz` and this node's
certificates are left as they are — both are real, current, and worth
keeping, not lab scratch to clean up.
