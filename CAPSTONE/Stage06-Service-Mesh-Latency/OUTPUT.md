# Capstone stage 06 — verified run

Captured **2026-09-28** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`
(4 CPU), flannel CNI unchanged. Linkerd **edge-26.9.3** (CLI, control plane
and viz). Applied over a running Stage 05. Result: **PASS** for L1–L5.
Linkerd, viz and the meshed capstone were **left installed**.

Two things went wrong on the way; both are now in the manual:
- with `limits.cpu: 3` the rolling restart hit `exceeded quota`, so the
  quota was raised to 4 (L2)
- the first viz install used `\d` in the host regex; `--set` stripped the
  backslash and `localhost:<port>` was refused, so the regex now uses
  `[0-9]` and `[.]` (L1)

## L1 — install

```console
$ LINKERD2_VERSION=edge-26.9.3 sh /tmp/linkerd-install.sh
$ linkerd version --client
Client version: edge-26.9.3

$ linkerd check --pre
gateway-api-crd
---------------
√ Gateway API CRDs are installed
...
Status check results are √

$ linkerd install --crds | kubectl apply -f -
$ linkerd install | kubectl apply -f -
$ linkerd check
...
Status check results are √
$ kubectl -n linkerd get pods
linkerd-destination-5f7fb4b46d-vpjmn      4/4     Running   0          55s
linkerd-identity-6b99c7475c-7tjw2         2/2     Running   0          56s
linkerd-proxy-injector-85bb678876-2c7rq   2/2     Running   0          55s

$ linkerd viz install --set dashboard.enforcedHostRegexp='^(localhost|127[.]0[.]0[.]1|linkerd-viz[.]k3s[.]local)(:[0-9]+)?$' | kubectl apply -f -
$ linkerd viz check
...
Status check results are √
$ kubectl -n linkerd-viz get pods
metrics-api-6b8c58bd49-v4wf9    2/2   Running
prometheus-55f769db-kgf29       2/2   Running
tap-65f7595cd8-8qw8m            2/2   Running
tap-injector-69f8d55d4b-jp76h   2/2   Running
web-65cf847496-95z79            2/2   Running

# host check
localhost:18084 -> 200
evil.example -> 400
ingress linkerd-viz.k3s.local -> 200

# the first attempt, with '(:\d+)?' in --set:
"-enforced-host=^(localhost|127.0.0.1|linkerd-viz.k3s.local)(:d+)?$"
localhost:18084 -> 400
It appears that you are trying to reach this service with a host of 'localhost:18084'.
```

## L2 — mesh the app

```console
$ kubectl apply -f manifests/
namespace/capstone configured
resourcequota/capstone-quota configured
...
deployment.apps/loadgen created
ingress.networking.k8s.io/linkerd-viz created
$ kubectl -n capstone rollout restart statefulset/redis deploy/api deploy/web

# with limits.cpu: "3" (first attempt), during the restart:
Error creating: pods "api-68b5c568f4-n8j6d" is forbidden: exceeded quota: capstone-quota, requested: limits.cpu=600m, used: limits.cpu=2750m, limited: limits.cpu=3

# with limits.cpu: "4": restart took 31s, no FailedCreate
$ kubectl -n capstone get pods
api-cb847dddd-m8dgz        2/2     Running   0          32s
api-cb847dddd-spwqr        2/2     Running   0          17s
loadgen-675c8d78f4-7zctc   2/2     Running   0          96s
redis-0                    2/2     Running   0          92s
web-8956b885f-nk5bp        2/2     Running   0          20s
web-8956b885f-x8w6d        2/2     Running   0          32s

Resource                Used    Hard
limits.cpu              2150m   4
limits.memory           1184Mi  2Gi
persistentvolumeclaims  1       2
pods                    6       10
requests.cpu            320m    1
requests.memory         456Mi   1Gi
```

## L3 — latency per hop

```console
$ linkerd viz stat deploy -n capstone
NAME      MESHED   SUCCESS      RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99   TCP_CONN
api          2/2   100.00%   3.9rps           3ms          12ms          31ms          6
loadgen      1/1   100.00%   0.3rps           1ms          92ms          98ms          1
web          2/2   100.00%   4.0rps           7ms          47ms         114ms          6

$ linkerd viz edges deploy -n capstone
SRC          DST       SRC_NS        DST_NS     SECURED
loadgen      web       capstone      capstone   √
web          api       capstone      capstone   √
prometheus   api       linkerd-viz   capstone   √
prometheus   loadgen   linkerd-viz   capstone   √
prometheus   web       linkerd-viz   capstone   √

$ linkerd viz edges po -n capstone | grep -E 'SRC|redis'
SRC                         DST                        SRC_NS        DST_NS     SECURED
api-cb847dddd-m8dgz         redis-0                    capstone      capstone   √
api-cb847dddd-spwqr         redis-0                    capstone      capstone   √
prometheus-55f769db-kgf29   redis-0                    linkerd-viz   capstone   √

$ linkerd viz stat deploy/web -n capstone --to deploy/api
NAME   MESHED   SUCCESS      RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99   TCP_CONN
web       2/2   100.00%   2.3rps           5ms          10ms          17ms          2

$ linkerd viz tap deploy/api -n capstone --path /api/hits
rsp id=1:0 proxy=in  src=10.42.0.252:60378 dst=10.42.0.253:8000 tls=true :status=200 latency=13307µs
rsp id=1:1 proxy=in  src=10.42.0.252:60378 dst=10.42.0.253:8000 tls=true :status=200 latency=4711µs
rsp id=1:2 proxy=in  src=10.42.0.252:60378 dst=10.42.0.253:8000 tls=true :status=200 latency=6160µs

# dashboard API through the Ingress:
$ curl -s --resolve linkerd-viz.k3s.local:80:$NODE_IP "http://linkerd-viz.k3s.local/api/tps-reports?resource_type=deployment&namespace=capstone"
{"ok":{"statTables":[{"podGroup":{"rows":[{"resource":{"namespace":"capstone", "type":"deployment", "name":"api"}, "timeWindow":"1m", ... "meshedPodCount":"2", ... "latencyMsP50":"3", ...
```

## L4 — slow client drill

```console
# before
api          2/2   100.00%   3.9rps           3ms          10ms          26ms          4
web          2/2   100.00%   4.0rps           7ms          52ms         161ms          7

$ kubectl apply -f drills/loadgen-slow.yaml
# during (1-minute window full)
NAME           MESHED   SUCCESS      RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99   TCP_CONN
api               2/2   100.00%   5.3rps         323ms         394ms         400ms         11
loadgen           1/1   100.00%   0.3rps           1ms           9ms          10ms          1
loadgen-slow      1/1   100.00%   0.1rps           1ms           1ms           1ms          1
web               2/2   100.00%   3.9rps          12ms         158ms         363ms          8

$ linkerd viz stat deploy/web -n capstone --to deploy/api
web       2/2   100.00%   2.7rps          13ms         188ms         275ms          4

nr_periods 604
nr_throttled 186
user request /api/hits: 0.022306s
user request /api/hits: 0.126558s
user request /api/hits: 0.165858s

$ kubectl delete -f drills/loadgen-slow.yaml
recovered after ~57s (1m rolling window)
api          2/2   100.00%   7.8rps           3ms           9ms          10ms          6
web          2/2   100.00%   3.9rps           6ms          11ms          36ms          9
```

## L5 — opaque TCP (redis)

```console
$ linkerd viz stat deploy/api -n capstone --to sts/redis
No traffic found.
$ linkerd viz stat sts/redis -n capstone -o wide
NAME    MESHED   SUCCESS      RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99   TCP_CONN   READ_BYTES/SEC   WRITE_BYTES/SEC
redis      1/1   100.00%   0.3rps           1ms           9ms          10ms          9          74.6B/s          866.3B/s
$ kubectl -n capstone exec redis-0 -c redis -- timeout 5 redis-cli --latency
0 2 0.32 97                     # min / max / avg ms / samples
```

## Compatibility check

Stage 05's `backup.sh` still works against the meshed redis (sidecar
present): `[2/4] copying redis data (counter = 405)`, AOF files copied.

## Left running (showcase)

```console
$ linkerd viz stat deploy -n capstone
NAME      MESHED   SUCCESS      RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99   TCP_CONN
api          2/2   100.00%   4.0rps           3ms          11ms          26ms          6
loadgen      1/1   100.00%   0.3rps           1ms           9ms          10ms          1
web          2/2   100.00%   4.0rps           8ms          40ms          79ms          7
```

Dashboard: http://linkerd-viz.k3s.local/ (hosts entry → 192.168.230.103).
