# Capstone stage 05 — Disruption budgets, backup and restore (Day 08)

## Scenario

The capstone app is healthy and budgeted (Stages 02–04). Now the operations
team wants two guarantees before anyone touches the cluster:

1. **Planned maintenance** (draining a node, an upgrade) must never take a
   whole tier offline at once.
2. If the namespace is lost, the app can be **rebuilt with its data**, and
   everyone knows how long that takes and how much data would be lost.

You add PodDisruptionBudgets, back the app up, delete it for real, and
restore it.

## What changed since Stage 04

| File | Change |
|---|---|
| `manifests/50-pdb.yaml` | **new**: PDB `minAvailable: 1` for `web` and `api`; deliberately none for `redis` |
| `scripts/evict.sh` | evicts one Pod through the Eviction API (what `kubectl drain` does) |
| `scripts/backup.sh` | redis data (AOF) + config + counter into `~/capstone-backups/<timestamp>` |
| `scripts/restore.sh` | rebuilds the namespace from a backup and checks the counter |

Manifests 00–40 are identical to Stage 04.

## Learning objectives

- explain what a PodDisruptionBudget protects against, and what it doesn't
- see an eviction refused (HTTP 429) and tell it apart from `kubectl delete pod`
- explain why a single-replica database gets **no** PDB
- back up an app's data **and** config, delete the namespace, and restore it
- measure RTO (how long the restore takes) and RPO (how much data is lost)

## Before starting

```bash
cd ~/Documents/k3s-training/CAPSTONE/Stage05-Disruption-Backup-Restore
kubectl -n capstone get pods          # Stage 04 running, 5 Pods 1/1
export NODE_IP=$(hostname -I | awk '{print $1}')
```

Behind? `kubectl apply -f ../Stage04-Startup-Limits/manifests/` first.

---

# Part A — The concept, on plain nginx (15 min)

[part-a-nginx/nginx-pdb-warmup.yaml](part-a-nginx/nginx-pdb-warmup.yaml): 2
nginx replicas, a PDB `minAvailable: 1`, and a readiness probe that waits
20s. The delay leaves a window where the replacement Pod isn't Ready yet.

```bash
kubectl apply -f part-a-nginx/nginx-pdb-warmup.yaml
kubectl -n capstone-warmup rollout status deploy/nginx
kubectl -n capstone-warmup get pdb nginx
```

Expected: `ALLOWED DISRUPTIONS 1` (2 Ready, at least 1 must stay).

### A1 — Evict one Pod: allowed

```bash
P1=$(kubectl -n capstone-warmup get pod -l app=nginx -o jsonpath='{.items[0].metadata.name}')
P2=$(kubectl -n capstone-warmup get pod -l app=nginx -o jsonpath='{.items[1].metadata.name}')
./scripts/evict.sh capstone-warmup $P1
kubectl -n capstone-warmup get pods
kubectl -n capstone-warmup get pdb nginx
```

Expected: `"status":"Success","code":201`. A replacement is starting (`0/1`)
and `ALLOWED DISRUPTIONS` is now `0`.

### A2 — Evict the second one straight away: refused

```bash
./scripts/evict.sh capstone-warmup $P2
```

Expected:

```
Error from server (TooManyRequests): Cannot evict pod as it would violate the pod's disruption budget.
```

Evicting it would leave 0 Ready Pods, below `minAvailable: 1`. `kubectl
drain` gets this same HTTP 429 and simply retries until it's allowed.

### A3 — Wait for the replacement, then try again

```bash
sleep 25
kubectl -n capstone-warmup get pdb nginx      # ALLOWED DISRUPTIONS 1 again
./scripts/evict.sh capstone-warmup $P2        # Success
```

### A4 — `kubectl delete` ignores the budget

```bash
kubectl -n capstone-warmup delete pod -l app=nginx --wait=false
kubectl -n capstone-warmup get pods
```

Expected: **both** Pods go at once and 0 are Ready for a few seconds. A PDB
only guards the **Eviction API** (drain, upgrades, autoscaler). It doesn't
stop `kubectl delete`, crashes, OOM kills or a node dying.

```bash
kubectl delete namespace capstone-warmup
```

> **Checkpoint A:** you can say which of evict / delete checks the PDB.

---

# Part B — The capstone app

## B1 — Deploy Stage 05 (3 min)

```bash
kubectl apply -f manifests/
kubectl -n capstone get pdb
```

Expected:

```
NAME   MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
api    1               N/A               1                     0s
web    1               N/A               1                     0s
```

Only the two PDBs are new; nothing restarts.

## B2 — Drill: evict both API Pods (5 min)

```bash
A1=$(kubectl -n capstone get pod -l app=api -o jsonpath='{.items[0].metadata.name}')
A2=$(kubectl -n capstone get pod -l app=api -o jsonpath='{.items[1].metadata.name}')
./scripts/evict.sh capstone $A1
./scripts/evict.sh capstone $A2
kubectl -n capstone get pods -l app=api
for i in 1 2 3; do curl -s --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits; echo; done
```

Expected: the first eviction succeeds, the second is refused (429), and
every request is answered by the API Pod that was kept:

```
api-...-5f8gl   0/1   Completed   0   5h51m
api-...-phcts   0/1   Running     0   3s
api-...-rn48s   1/1   Running     1   5h51m
{"hits":31,"pod":"api-...-rn48s","version":"1.0.0"}
```

> **Checkpoint B2:** the API never had 0 Ready Pods during the evictions.

## B3 — Why redis has no PDB (5 min)

redis runs **one** replica. A PDB that protects it (`minAvailable: 1`)
allows **zero** evictions, so `kubectl drain` would retry forever and the
node could never be maintained. Without a PDB it can be evicted, and the app
has a short outage:

```bash
./scripts/evict.sh capstone redis-0
kubectl -n capstone rollout status statefulset/redis
kubectl -n capstone exec redis-0 -- redis-cli GET hits
```

Expected: `Success`, redis is back in ~10s, and the counter is unchanged:
the data lives on the PVC, not in the Pod. Watch the site while it happens
(run the loop right after the eviction):

```bash
for i in $(seq 1 15); do curl -s -w ' HTTP %{http_code}\n' --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits; sleep 1; done
```

```
{"error":"redis unavailable: Error -2 connecting to redis:6379. Name or service not known.",...} HTTP 503
...                                                    (about 9 s of these)
<html><head><title>502 Bad Gateway</title>...          (API Pods NotReady for a moment)
{"hits":37,"pod":"api-...","version":"1.0.0"} HTTP 200
```

The API answers 503 while redis is gone, then briefly the API Pods are
NotReady too (their `/ready` pings redis) and nginx returns 502.

A singleton is protected by **backups** (B4–B7) and a fast restart, not by
a PDB. The real fix is more replicas (redis replication or Sentinel), out of
scope here.

**What would a drain do?** A server-side dry run shows the list without
evicting anything:

```bash
kubectl drain $(kubectl get node -o jsonpath='{.items[0].metadata.name}') \
  --ignore-daemonsets --delete-emptydir-data --dry-run=server \
  --pod-selector=app.kubernetes.io/part-of=capstone
```

```
node/lab-g2-vm2 cordoned (server dry run)
evicting pod capstone/web-... (server dry run)
evicting pod capstone/api-... (server dry run)
evicting pod capstone/redis-0 (server dry run)
...
node/lab-g2-vm2 drained (server dry run)
```

The dry run checks each eviction on its own, so it can't show the budget
kicking in. A **real** drain on this single-node cluster would evict one
`api` and one `web` Pod, then get 429 for the second of each **forever**:
the node is cordoned, so the replacements can't be scheduled anywhere and
never become Ready. On a single node, `minAvailable: 1` and a drain can't
both be satisfied. Don't run a real drain here.

> **Checkpoint B3:** you can explain why a PDB on a 1-replica workload
> blocks maintenance instead of protecting anything.

## B4 — Back up (5 min)

```bash
./scripts/backup.sh ~/capstone-backups/stage05-drill
cat ~/capstone-backups/stage05-drill/backup-info.txt
```

Expected:

```
[1/4] compacting the AOF (BGREWRITEAOF)
[2/4] copying redis data (counter = 34)
tar: removing leading '/' from member names
[3/4] saving the deployed config
[4/4] writing backup-info.txt
backup complete: /home/labuser/capstone-backups/stage05-drill
...
date:   2026-09-28T17:41:59+05:30
hits:   34
images:
  api-...: localhost:5000/capstone-api:1.0.0
  ...
```

| What | Where in the backup | Why |
|---|---|---|
| redis data | `appendonlydir/` | redis runs `--appendonly yes`; on startup redis 7 loads **only** the AOF files |
| config | `app.yaml` | this stage's manifests, joined into one file |
| facts | `backup-info.txt` | when, which images, the counter (used to check the restore) |

The `tar: removing leading '/'` line is `kubectl cp` being chatty; it's
harmless.

> **Checkpoint B4:** `backup-info.txt` shows the current counter.

## B5 — Write some data after the backup (1 min)

```bash
for i in 1 2 3; do curl -s --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits; echo; done
```

Note the last value (37 in the reference run). These 3 hits are **not** in
the backup.

## B6 — Disaster: delete the namespace (2 min)

```bash
PV=$(kubectl -n capstone get pvc data-redis-0 -o jsonpath='{.spec.volumeName}')
kubectl delete namespace capstone
kubectl get pv $PV
curl -s -o /dev/null -w 'site: HTTP %{http_code}\n' --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/
```

Expected:

```
namespace "capstone" deleted
Error from server (NotFound): persistentvolumes "pvc-..." not found
site: HTTP 404
```

The **volume is gone too**. The `local-path` StorageClass has reclaim policy
`Delete`: when the PVC went with the namespace, the PV and its data on disk
went with it. Only the backup has the data now.

## B7 — Restore (5 min)

```bash
./scripts/restore.sh ~/capstone-backups/stage05-drill
kubectl -n capstone get pods,pvc,pdb
for i in 1 2; do curl -s --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits; echo; done
```

Expected:

```
[1/5] applying the backed-up config
[2/5] stopping redis
[3/5] copying data into the volume via a helper Pod
[4/5] starting redis
[5/5] checking
counter in backup: 34   counter now: 34
restore took 42 s
RESTORE OK
...
{"hits":35,"pod":"api-...","version":"1.0.0"}
```

The script's order matters: it creates everything, then **stops redis**
before writing to its new, empty volume. A running redis would save its own
empty data on shutdown and overwrite the restore. A throw-away helper Pod
mounts the PVC, the AOF files are copied in, and redis starts and loads them.

> **Checkpoint B7:** `RESTORE OK`, and the next hit continues from the
> backup's value.

## B8 — RTO and RPO (5 min)

| | Meaning | This run |
|---|---|---|
| **RTO** (recovery time objective) | how long from "start restoring" to "serving again" | **42 s** (`restore took`) |
| **RPO** (recovery point objective) | how much data you can lose: everything since the last backup | **3 hits** (35–37 were written after the backup, then lost) |

RPO is set by **how often you back up**, not by how good the restore is.
Hourly backups mean up to an hour of lost data. Take the backup more often,
or replicate the data, to shrink it.

> **Checkpoint B8:** you can state this app's RTO and RPO, and name the one
> change that would shrink each.

---

## Troubleshooting

| Symptom | Likely cause / check |
|---|---|
| second eviction in A2/B2 **succeeds** | the replacement became Ready first. In A2, evict within ~20s; in B2, run both lines together |
| `evict.sh` prints `Success` for redis in B3 | expected: redis has no PDB. It's back in ~10s |
| a real `kubectl drain` hangs on `api`/`web` | expected on one node (B3). Ctrl-C, then `kubectl uncordon <node>` |
| backup: `Error from server (NotFound): pods "redis-0"` | redis isn't running: `kubectl -n capstone get pods` |
| restore stops at `[1/5]` or `[4/5]` | a Pod can't start: `kubectl -n capstone get pods`, then `describe` it. Often the registry isn't running: `docker start capstone-registry` |
| `RESTORE MISMATCH` | redis started before the data was copied. Re-run `restore.sh`; it's safe to repeat |
| namespace stuck `Terminating` | wait; the PVC is released once all Pods have stopped |

## Before you leave — keep it running

The restored app is the starting point for
[Stage 06](../Stage06-Service-Mesh-Latency/LAB-MANUAL.md) (Linkerd service mesh, latency
per hop). To catch up later:

```bash
kubectl apply -f CAPSTONE/Stage05-Disruption-Backup-Restore/manifests/
```
