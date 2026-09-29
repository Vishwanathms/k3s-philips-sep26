# Capstone stage 05 — verified run

Captured **2026-09-28** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
applied over a running Stage 04. Result: **PASS** for Part A and B1–B8.
RTO **42 s**, RPO **3 hits**.

## Part A — nginx PDB warm-up

```console
$ kubectl apply -f part-a-nginx/nginx-pdb-warmup.yaml
namespace/capstone-warmup created
deployment.apps/nginx created
poddisruptionbudget.policy/nginx created
$ kubectl -n capstone-warmup get pdb nginx
NAME    MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
nginx   1               N/A               1                     28s

# A1
$ ./scripts/evict.sh capstone-warmup nginx-bcd585b4b-rm29g
{"kind":"Status","apiVersion":"v1","metadata":{},"status":"Success","code":201}
nginx-bcd585b4b-qmwgv   0/1     ContainerCreating   0          3s
nginx-bcd585b4b-rqmtq   1/1     Running             0          34s
nginx   1               N/A               0                     34s

# A2
$ ./scripts/evict.sh capstone-warmup nginx-bcd585b4b-rqmtq
Error from server (TooManyRequests): Cannot evict pod as it would violate the pod's disruption budget.

# A3 (25 s later)
nginx-bcd585b4b-qmwgv   1/1     Running   0          29s
nginx-bcd585b4b-rqmtq   1/1     Running   0          60s
nginx   1               N/A               1                     61s
$ ./scripts/evict.sh capstone-warmup nginx-bcd585b4b-rqmtq
{"kind":"Status","apiVersion":"v1","metadata":{},"status":"Success","code":201}

# A4 — delete bypasses the PDB (ALLOWED DISRUPTIONS was 1, both went)
$ kubectl -n capstone-warmup delete pod -l app=nginx --wait=false
nginx-bcd585b4b-952vr   0/1     ContainerCreating   0          3s
nginx-bcd585b4b-c9r66   0/1     Completed           0          35s
nginx-bcd585b4b-qfh46   0/1     ContainerCreating   0          3s
nginx-bcd585b4b-qmwgv   0/1     Completed           0          65s
$ kubectl delete namespace capstone-warmup
```

## B1 — deploy Stage 05

```console
$ kubectl apply -f manifests/
...
poddisruptionbudget.policy/web created
poddisruptionbudget.policy/api created
$ kubectl -n capstone get pdb
NAME   MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
api    1               N/A               1                     0s
web    1               N/A               1                     0s
```

## B2 — evict both API Pods

```console
$ ./scripts/evict.sh capstone api-5bd4687f9d-5f8gl
{"kind":"Status","apiVersion":"v1","metadata":{},"status":"Success","code":201}
$ ./scripts/evict.sh capstone api-5bd4687f9d-rn48s
Error from server (TooManyRequests): Cannot evict pod as it would violate the pod's disruption budget.
api-5bd4687f9d-5f8gl   0/1     Completed   0               5h51m
api-5bd4687f9d-phcts   0/1     Running     0               3s
api-5bd4687f9d-rn48s   1/1     Running     1 (5h36m ago)   5h51m
api   1     N/A   0     5s
{"hits":31,"pod":"api-5bd4687f9d-rn48s","version":"1.0.0"}
{"hits":32,"pod":"api-5bd4687f9d-rn48s","version":"1.0.0"}
{"hits":33,"pod":"api-5bd4687f9d-rn48s","version":"1.0.0"}
```

## B3 — evict redis (no PDB), drain dry run

```console
$ ./scripts/evict.sh capstone redis-0
{"kind":"Status","apiVersion":"v1","metadata":{},"status":"Success","code":201}
 1s {"error":"redis unavailable: Error -2 connecting to redis:6379. Name or service not known.","pod":"api-5bd4687...
...
 9s {"error":"redis unavailable: Error -2 connecting to redis:6379. Name or service not known.","pod":"api-5bd4687...
10s <html><head><title>502 Bad Gateway</title></head>...
11s {"hits":37,"pod":"api-5bd4687f9d-77tg7","version":"1.0.0"} HTTP 200
...
15s {"hits":41,"pod":"api-5bd4687f9d-77tg7","version":"1.0.0"} HTTP 200
redis-0   1/1   Running   0     15s
```

(This loop is from after the restore, hence hits 37+. The first redis
eviction, before the backup, kept the counter at 33 → 34 the same way.)

```console
$ kubectl drain lab-g2-vm2 --ignore-daemonsets --delete-emptydir-data --dry-run=server --pod-selector=app.kubernetes.io/part-of=capstone
node/lab-g2-vm2 cordoned (server dry run)
evicting pod capstone/web-8697c555b5-rqbss (server dry run)
evicting pod capstone/api-5bd4687f9d-rn48s (server dry run)
evicting pod capstone/redis-0 (server dry run)
evicting pod capstone/api-5bd4687f9d-phcts (server dry run)
evicting pod capstone/web-8697c555b5-bsbbb (server dry run)
node/lab-g2-vm2 drained (server dry run)
$ kubectl get node lab-g2-vm2 -o jsonpath='{.spec.unschedulable}'
                                   # empty: the node was not really cordoned
```

## B4 — backup

```console
$ ./scripts/backup.sh ~/capstone-backups/stage05-drill
[1/4] compacting the AOF (BGREWRITEAOF)
[2/4] copying redis data (counter = 34)
tar: removing leading '/' from member names
[3/4] saving the deployed config
[4/4] writing backup-info.txt

backup complete: /home/labuser/capstone-backups/stage05-drill
-rw-rw-r-- 1 labuser labuser 102 Sep 28 17:41 appendonly.aof.3.base.rdb
-rw-rw-r-- 1 labuser labuser   0 Sep 28 17:41 appendonly.aof.3.incr.aof
-rw-rw-r-- 1 labuser labuser  88 Sep 28 17:41 appendonly.aof.manifest

$ cat ~/capstone-backups/stage05-drill/backup-info.txt
date:   2026-09-28T17:41:59+05:30
hits:   34
images:
  api-5bd4687f9d-phcts: localhost:5000/capstone-api:1.0.0
  api-5bd4687f9d-rn48s: localhost:5000/capstone-api:1.0.0
  redis-0: redis:7-alpine
  web-8697c555b5-bsbbb: localhost:5000/capstone-web:1.0.0
  web-8697c555b5-rqbss: localhost:5000/capstone-web:1.0.0
# app.yaml: 12 objects, passes kubectl apply --dry-run=client
```

## B5 — data after the backup

```console
{"hits":35,"pod":"api-5bd4687f9d-rn48s","version":"1.0.0"}
{"hits":36,"pod":"api-5bd4687f9d-rn48s","version":"1.0.0"}
{"hits":37,"pod":"api-5bd4687f9d-phcts","version":"1.0.0"}
```

## B6 — delete the namespace

```console
$ kubectl delete namespace capstone
namespace "capstone" deleted                       # took 37 s
$ kubectl get pv pvc-4b1546a3-30d7-4ebc-8ab6-32888bc7e278
Error from server (NotFound): persistentvolumes "pvc-4b1546a3-30d7-4ebc-8ab6-32888bc7e278" not found
site: HTTP 404
```

## B7 — restore

```console
$ ./scripts/restore.sh ~/capstone-backups/stage05-drill
[1/5] applying the backed-up config
[2/5] stopping redis
[3/5] copying data into the volume via a helper Pod
[4/5] starting redis
[5/5] checking
counter in backup: 34   counter now: 34
restore took 42 s
RESTORE OK

$ kubectl -n capstone get pods,pvc,pdb
pod/api-5bd4687f9d-5klp7   1/1     Running   0          41s
pod/api-5bd4687f9d-77tg7   1/1     Running   0          41s
pod/redis-0                1/1     Running   0          17s
pod/web-8697c555b5-88wgk   1/1     Running   0          41s
pod/web-8697c555b5-gs5h4   1/1     Running   0          41s
persistentvolumeclaim/data-redis-0   Bound    pvc-a255cb68-d116-4f12-8303-aaf1f0f68045   1Gi   RWO   local-path
poddisruptionbudget.policy/api   1   N/A   1   42s
poddisruptionbudget.policy/web   1   N/A   1   42s
{"hits":35,"pod":"api-5bd4687f9d-77tg7","version":"1.0.0"}
{"hits":36,"pod":"api-5bd4687f9d-5klp7","version":"1.0.0"}
```

New PV (`pvc-a255cb68-…`), same data. Hits 35–37 from B5 were lost and
re-counted: RPO = 3 hits. RTO = 42 s.

Final state: Stage 05 running in `capstone`, 5 Pods `1/1`, 2 PDBs.
A safety backup taken before B6 is at `~/capstone-backups/safety-174151`.
