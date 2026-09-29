# Day 08 — Cluster Maintenance, Backup & Restore

Builds directly on:

- **Day 01–07:** workloads, Services, Secrets, RBAC, networking internals,
  Ingress, storage, and resource governance — everything this day's
  backup/restore labs prove survives intact.

This module is about keeping the cluster itself alive: cordoning and
draining a node for maintenance, rotating its certificates, and backing up
and restoring its entire state — for real, with real downtime measured in
seconds, not assumed.

| Material | Purpose |
|---|---|
| [slides/PPT_CONTENT.md](slides/PPT_CONTENT.md) | Detailed slide-by-slide teaching content, presenter cues, and sources |
| [slides/Day-08-Cluster-Maintenance-Backup-Restore.pptx](slides/Day-08-Cluster-Maintenance-Backup-Restore.pptx) | Presentation-ready PowerPoint deck |

## Hands-on labs

| # | Lab | Proves | Verified run |
|---|-----|--------|--------------|
| 1 | [ex01-node-cordoning](ex01-node-cordoning/) | cordoning stops new Pods scheduling, leaves everything running untouched | [OUTPUT.md](ex01-node-cordoning/OUTPUT.md) |
| 2 | [ex02-node-drain](ex02-node-drain/) | real `kubectl drain --dry-run=client` output — exactly what would be evicted, safely | [OUTPUT.md](ex02-node-drain/OUTPUT.md) |
| 3 | [ex03-certificate-rotation](ex03-certificate-rotation/) | a real, executed `k3s certificate rotate` + restart — new serials, ~2s downtime, old certs auto-backed-up | [OUTPUT.md](ex03-certificate-rotation/OUTPUT.md) |
| 4 | [ex04-backup](ex04-backup/) | a real file-level backup of the SQLite datastore (`etcd-snapshot` refuses — this isn't etcd) | [OUTPUT.md](ex04-backup/OUTPUT.md) |
| 5 | [ex05-restore](ex05-restore/) | delete a namespace for real, restore it for real from ex04's backup, byte-for-byte | [OUTPUT.md](ex05-restore/OUTPUT.md) |
| 6 | [ex06-disaster-recovery](ex06-disaster-recovery/) | a runbook tying it together — what recovers on its own, RTO/RPO measured from the real runs above, a scheduling + pruning plan | (runbook, not a captured run) |

Also: [design-upgrade-strategy.md](design-upgrade-strategy.md) — the real
k3s upgrade procedure, rehearsed and explained but **not executed** on this
cluster (see below).

Start with [LAB-MANUAL.md](LAB-MANUAL.md). Labs 1, 3, 4, and 5 were run for
real against this cluster on **2026-09-13** — every lab's own `OUTPUT.md`
has the full captured transcript.

```bash
kubectl delete namespace canary 2>/dev/null   # if a lab run is interrupted mid-way
```

## What was executed for real vs. rehearsed only

This is the one day in the course that touches the cluster's own control
plane and data, not just workloads inside it — so the scope here was
explicitly agreed before building it:

| Lab | Executed for real? |
|---|---|
| Cordon/uncordon | **Yes** — no disruption risk, fully reversible instantly |
| Drain | `--dry-run=client` only — a real drain would evict Traefik, CoreDNS, the CSI controller, etc. with nowhere else to reschedule to on this one-node cluster |
| Certificate rotation | **Yes** — real `k3s certificate rotate` + restart, ~2s downtime, k3s auto-backs-up the old certs |
| Backup | **Yes** — real stop/tar/start of the live datastore |
| Restore | **Yes** — a real namespace was deleted and restored from that backup |
| k3s version upgrade | **Not executed** — k3s doesn't support downgrading a server, so a real version change is a one-way door affecting every other day sharing this node. Procedure and real commands are in `design-upgrade-strategy.md`, rehearsed rather than run — same precedent as Day 04's CNI-migration content. |

## Capstone stage 05

After the labs above, students apply today's topics to the course capstone:
PodDisruptionBudgets on the web and api tiers (and why redis gets none),
then back up the app, delete its namespace for real, restore it with the
counter preserved, and measure RTO/RPO. Manual:
[CAPSTONE/Stage05-Disruption-Backup-Restore/LAB-MANUAL.md](../CAPSTONE/Stage05-Disruption-Backup-Restore/LAB-MANUAL.md).

## Prerequisites

```bash
kubectl get nodes                              # Ready
sudo k3s certificate check                     # cert status/expiry
sudo test -d /var/lib/rancher/k3s/server/db && echo "SQLite datastore (as expected on a single server)"
```
