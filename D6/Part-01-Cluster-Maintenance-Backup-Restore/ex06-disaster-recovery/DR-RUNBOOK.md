# Disaster recovery runbook — this cluster

This ties ex01–ex05 together into one runbook, plus the parts of "disaster
recovery" that are genuinely bigger than a single lab: what actually counts
as a disaster here, what recovers automatically, and what needs a human
running ex04/ex05's scripts.

## What "disaster" means on a single-node cluster

There is no distinction between "a node failed" and "the cluster failed" —
they're the same node. Concretely, on **this** cluster:

| Event | Recovers on its own? | What actually brings it back |
|---|---|---|
| A Pod crashes | Yes — its controller (Deployment/StatefulSet/DaemonSet) recreates it | nothing — this is the normal self-healing loop from Day 01/07 |
| The node reboots | Mostly — `k3s.service` is `enabled`, Pods reschedule | nothing, if disks are intact |
| The k3s **datastore** is corrupted/lost (disk failure, bad `rm -rf`, bad upgrade) | **No** | `ex05`'s restore, from an `ex04` backup made *before* the loss |
| The whole VM/disk is destroyed | **No** | a backup that was copied **off** this VM (ex04's `.tar.gz` alone, sitting on the same disk, does not survive this) |

The last row is the gap every single-node lab in this course shares: a
backup stored on the same disk as what it's backing up survives a
`rm -rf` of the wrong directory, but not a lost VM/disk. Copying `ex04`'s
`.tar.gz` somewhere else (another host, object storage) is what closes that
gap — this course doesn't have a second location to demonstrate that copy
step against, so it's a checklist item here, not a lab.

## RTO / RPO, measured, not estimated

From `ex04`/`ex05`'s actual captured runs:

- **RTO** (how long you're down) ≈ the `systemctl stop` → `systemctl start`
  → API-responding window: **~2 seconds** on this node's data size, for
  *both* backup and restore.
- **RPO** (how much you can lose) = the age of your most recent backup.
  A backup taken every night loses up to a day of changes; one taken every
  5 minutes loses up to 5 minutes. `ex04`'s script takes long enough
  (dominated by `tar`, not by k3s itself) that running it every few minutes
  on a busy cluster would need the archive step optimized (e.g.
  `--exclude` for anything regenerable) — a real capacity-planning
  question, not just a cron entry.

## The runbook

**Routine backup** (schedule this — see below):

```bash
bash ex04-backup/backup-datastore.sh /root/k3s-backups
# then COPY the resulting .tar.gz off this VM - not shown here, no second
# location exists in this course to copy it to
```

**Suspected datastore corruption / bad change:**

```bash
kubectl get nodes                      # confirm the API is actually unhealthy first -
                                        # don't restore over a problem that isn't a data problem
bash ex05-restore/restore-datastore.sh /root/k3s-backups/<latest>.tar.gz
kubectl get nodes
kubectl get pods -A                    # confirm every workload came back
```

**Scheduling the backup for real** (a real, safe crontab line — not
installed by this lab, since a recurring root cron job outlives the
training session):

```cron
# every day at 02:00
0 2 * * * /usr/bin/bash /home/labuser/Documents/k3s-training/Day-08-Cluster-Maintenance-Backup-Restore/ex04-backup/backup-datastore.sh /root/k3s-backups >> /var/log/k3s-backup.log 2>&1
```

**Pruning old backups** (so `/root/k3s-backups` doesn't grow forever):

```bash
find /root/k3s-backups -name '*.tar.gz' -mtime +14 -delete   # keep 14 days
```

## Checklist

- [ ] A backup exists that is **newer** than your RPO target.
- [ ] That backup has been copied to a **different** disk/host at least
      once (untested in this course — no second location available).
- [ ] You know exactly which command restores it (`ex05-restore/restore-datastore.sh`)
      and have practiced running it at least once, before you need it for real.
- [ ] After any restore, you check `kubectl get pods -A` for **every**
      namespace, not just the one you were worried about — Day 06's CSI
      driver and Day 07's ResourceQuota are just as much "state" as an app.
- [ ] Node maintenance always starts with `cordon` (`ex01`), and a real
      `drain` (`ex02`) is only skipped here because there's no second node
      to move workload to — do not skip it on a real multi-node cluster.
