# Capstone stage 04 — verified run

Captured **2026-09-28** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`
(4 CPU), cgroup v2. Applied over a running Stage 03. Result: **PASS** for
S0–S5.

> While building S1 the first version used a 45s sleep with a 60s startup
> budget. It failed: gunicorn answered at ~54s (45s + ~9s boot under a 200m
> CPU limit) and the startup probe gave up at 60s. The drill was changed to a
> 30s sleep and a 90s budget. That failure is the "size the budget with
> margin" note in the manual.

## S0 — deploy Stage 04

```console
$ kubectl apply -f manifests/
namespace/capstone unchanged
limitrange/capstone-defaults unchanged
resourcequota/capstone-quota unchanged
service/redis unchanged
statefulset.apps/redis configured
deployment.apps/api configured
service/api unchanged
deployment.apps/web unchanged
service/web unchanged
ingress.networking.k8s.io/capstone unchanged

$ kubectl -n capstone get pods
api-5bd4687f9d-5f8gl   1/1     Running   0          29s
api-5bd4687f9d-rn48s   1/1     Running   0          15s
redis-0                1/1     Running   0          28s
web-8697c555b5-bsbbb   1/1     Running   0          17m
web-8697c555b5-rqbss   1/1     Running   0          17m

$ kubectl -n capstone describe pod -l app=api | grep -E '^Name:|Startup:|Liveness:'
Name:             api-5bd4687f9d-5f8gl
    Liveness:   http-get http://:http/healthz delay=0s timeout=1s period=10s #success=1 #failure=3
    Startup:    http-get http://:http/healthz delay=0s timeout=1s period=2s #success=1 #failure=30
Name:             api-5bd4687f9d-rn48s
    Liveness:   http-get http://:http/healthz delay=0s timeout=1s period=10s #success=1 #failure=3
    Startup:    http-get http://:http/healthz delay=0s timeout=1s period=2s #success=1 #failure=30

# redis startupProbe:
{"exec":{"command":["redis-cli","ping"]},"failureThreshold":30,"periodSeconds":2,"successThreshold":1,"timeoutSeconds":1}

{"hits":27,"pod":"api-5bd4687f9d-rn48s","version":"1.0.0"}
```

## S1a — slow start, liveness only

```console
$ kubectl apply -f drills/api-slow-no-startup.yaml
$ kubectl -n capstone get pods -l app=api-slow        # after 150s
api-slow-597f66fb6c-j7kck   0/1     Running   4 (29s ago)   2m30s
      Exit Code:    143
    Restart Count:  4
    Liveness:     http-get http://:http/healthz delay=5s timeout=1s period=10s #success=1 #failure=3
  Warning  Unhealthy  91s (x6 over 2m21s)   Liveness probe failed: Get "http://10.42.0.217:8000/healthz": dial tcp 10.42.0.217:8000: connect: connection refused
  Warning  Unhealthy  85s (x19 over 2m29s)  Readiness probe failed: Get "http://10.42.0.217:8000/healthz": dial tcp 10.42.0.217:8000: connect: connection refused
  Normal   Killing    1s (x5 over 2m1s)     Container api failed liveness probe, will be restarted
booting slowly (30s)

# an earlier run of the same drill, at 180s:
api-slow-58644b8dcf-27nxw   0/1   CrashLoopBackOff   4 (32s ago)   3m2s
```

## S1b — slow start, with startup probe

```console
$ kubectl apply -f drills/api-slow-with-startup.yaml
$ kubectl -n capstone rollout status deploy/api-slow --timeout=150s
deployment "api-slow" successfully rolled out
api-slow-85c95774b6-mmdlk   1/1     Running   0          53s
    Restart Count:  0
    Liveness:     http-get http://:http/healthz delay=0s timeout=1s period=10s #success=1 #failure=3
    Startup:      http-get http://:http/healthz delay=0s timeout=1s period=2s #success=1 #failure=45
  Normal   Started    52s                 Container started
  Warning  Unhealthy  14s (x20 over 52s)  Startup probe failed: Get "http://10.42.0.218:8000/healthz": dial tcp 10.42.0.218:8000: connect: connection refused
  Warning  Unhealthy  3s (x5 over 11s)    Startup probe failed: Get "http://10.42.0.218:8000/healthz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
booting slowly (30s)
[2026-09-28 06:34:01 +0000] [1] [INFO] Starting gunicorn 23.0.0
[2026-09-28 06:34:01 +0000] [1] [INFO] Listening at: http://0.0.0.0:8000 (1)
$ kubectl -n capstone delete deploy api-slow
```

25 startup failures out of 45 allowed; no restart.

## S2 — CPU throttling (api, `limits.cpu: 500m`)

```console
$ kubectl -n capstone exec api-5bd4687f9d-5f8gl -- cat /sys/fs/cgroup/cpu.max
50000 100000
before: usage_usec 6216994 nr_periods 884 nr_throttled 88 throttled_usec 3938839
{"burned_ms":2000,"loops":2706023,"pod":"api-5bd4687f9d-5f8gl"}
  wall=2.026403s
after:  usage_usec 7282562 nr_periods 907 nr_throttled 109 throttled_usec 4441991
```

2.03s wall, +1,065,568 µs CPU (≈ 0.5 core); 21 of 23 periods throttled.

## S3 — OOMKilled (api, `limits.memory: 256Mi`)

```console
$ kubectl -n capstone exec api-5bd4687f9d-rn48s -- cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.oom.group
268435456
67702784
1
$ kubectl -n capstone exec api-5bd4687f9d-rn48s -- python -c '...'
16 MiB
...
176 MiB
command terminated with exit code 137

$ kubectl -n capstone get pods -l app=api
api-5bd4687f9d-5f8gl   1/1     Running   0            15m
api-5bd4687f9d-rn48s   0/1     Running   1 (6s ago)   15m
OOMKilled exit=137 restarts=1
  Unhealthy   Startup probe failed: Get "http://10.42.0.211:8000/healthz": dial tcp 10.42.0.211:8000: connect: connection refused
{"hits":28,"pod":"api-5bd4687f9d-5f8gl","version":"1.0.0"}
{"hits":29,"pod":"api-5bd4687f9d-5f8gl","version":"1.0.0"}
{"hits":30,"pod":"api-5bd4687f9d-5f8gl","version":"1.0.0"}
```

`rn48s` was back to `1/1` within ~20s.

## S4 — admission vs scheduling

```console
4 cpu allocatable

# capstone (LimitRange + quota):
Error from server (Forbidden): pods "big" is forbidden: maximum cpu usage per Container is 1, but limit is 8

# capstone-scratch (no governance):
pod/big created
big    0/1     Pending   0          6s
0/1 nodes are available: 1 Insufficient cpu. no new claims to deallocate, preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
```

## S5 — oom_score_adj per QoS class

```console
redis-0                    Guaranteed  oom_score_adj=-997
api-5bd4687f9d-5f8gl       Burstable   oom_score_adj=998
web-8697c555b5-bsbbb       Burstable   oom_score_adj=999
besteffort                 BestEffort  oom_score_adj=1000
$ kubectl delete namespace capstone-scratch
```

Final state: Stage 04 running in `capstone`, 5 Pods `1/1`, no drill objects
left.
