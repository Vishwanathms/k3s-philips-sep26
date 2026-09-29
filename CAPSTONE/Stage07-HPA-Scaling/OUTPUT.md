# Capstone stage 07 — verified run

Captured **2026-09-28** on k3s `v1.36.4+k3s1` (API `v1.36.3`), single node
`lab-g2-vm2` (4 CPU), metrics-server built in, VPA `1.7.1` (installed on
Day 09), Linkerd `edge-26.9.3` (Stage 06). Applied over a running Stage 06.
Result: **PASS** for H1–H6.

## H3 — apply

```console
$ kubectl apply -f manifests/
resourcequota/capstone-quota configured
statefulset.apps/redis configured
deployment.apps/api configured
poddisruptionbudget.policy/web configured
poddisruptionbudget.policy/api configured
horizontalpodautoscaler.autoscaling/api created
verticalpodautoscaler.autoscaling.k8s.io/web created
verticalpodautoscaler.autoscaling.k8s.io/redis created

# the one-time replicas dip (replicas: removed from 20-api.yaml)
18:21:49 spec=1 ready=1 hpa=/0
18:21:59 spec=1 ready=1 hpa=/0
18:22:03 spec=2 ready=1 hpa=1/2
18:22:25 spec=2 ready=2 hpa=2/2

$ kubectl -n capstone get hpa api
NAME   REFERENCE        TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
api    Deployment/api   cpu: 18%/60%   2         6         2          42s
Normal  SuccessfulRescale  ...  New size: 2; reason: Current number of replicas below Spec.MinReplicas
```

## H4 — 4 workers × 200 ms, 180 s, through the Ingress

```console
$ ./scripts/load.sh 4 180 200
load: 4 workers x 200ms CPU per request, 180s, via 192.168.230.103
worker 2: 507 requests
worker 4: 509 requests
worker 3: 513 requests
worker 1: 518 requests
load: done

# kubectl -n capstone get hpa api, every 15 s
18:22:46 cpu: 18%/60% replicas=2
18:23:02 cpu: 11%/60% replicas=2
18:23:18 cpu: 330%/60% replicas=2
18:23:34 cpu: 461%/60% replicas=6
18:23:50 cpu: 383%/60% replicas=6
...
18:25:59 cpu: 396%/60% replicas=6
# load ends ~18:26:00
18:26:45 cpu: 6%/60% replicas=6
18:27:01 cpu: 9%/60% replicas=6
18:27:16 cpu: 6%/60% replicas=6
18:27:32 cpu: 6%/60% replicas=2

Events:
  Normal  SuccessfulRescale  ...  New size: 2; reason: Current number of replicas below Spec.MinReplicas
  Normal  SuccessfulRescale  ...  New size: 6; reason: cpu container resource utilization (percentage of request) above target
  Normal  SuccessfulRescale  ...  New size: 2; reason: All metrics below target

# quota at 6 api Pods
limits.cpu              4550m   6
limits.memory           2464Mi  3Gi
persistentvolumeclaims  1       2
pods                    10      15
requests.cpu            560m    1
requests.memory         792Mi   1Gi
```

## H5 — does scaling help? (readings at ~80 s into a 100 s load)

4 workers (fits into 2 Pods × 2 gunicorn workers, nothing queues):

```console
--- maxReplicas=2
hpa: cpu: 859%/60% replicas=2
api       2/2   100.00%   15.4rps         235ms         294ms         300ms          9
--- maxReplicas=6
hpa: cpu: 410%/60% replicas=6
api       6/6   100.00%   18.4rps         225ms         292ms         298ms         19
```

12 workers (queues with 2 Pods):

```console
--- maxReplicas=2
hpa: cpu: 972%/60% replicas=2
api       2/2   100.00%   20.9rps         428ms         930ms         986ms         18
users (loadgen -> web): loadgen      1/1   100.00%   1.7rps         250ms         575ms         915ms          2
--- maxReplicas=6
hpa: cpu: 554%/60% replicas=6
api       6/6   100.00%   32.2rps         239ms         298ms         389ms         27
users (loadgen -> web): loadgen      1/1   100.00%   3.0rps          16ms          92ms         168ms          2

$ kubectl apply -f manifests/55-hpa-api.yaml      # maxReplicas back to 6
```

## H6 — VPA recommendations

```console
$ kubectl -n capstone get vpa
NAME    MODE   CPU   MEM     PROVIDED   AGE
redis   Off    35m   250Mi   True       17m
web     Off    25m   250Mi   True       17m

$ kubectl -n capstone get vpa web -o jsonpath='{.status.recommendation.containerRecommendations[0]}'
{"containerName":"web","lowerBound":{"cpu":"25m","memory":"250Mi"},"target":{"cpu":"25m","memory":"250Mi"},"uncappedTarget":{"cpu":"25m","memory":"250Mi"},"upperBound":{"cpu":"39m","memory":"250Mi"}}

$ kubectl top pods -n capstone --containers | grep -E 'NAME|web|redis'
POD                        NAME            CPU(cores)   MEMORY(bytes)
redis-0                    linkerd-proxy   3m           3Mi
redis-0                    redis           20m          3Mi
web-8956b885f-nk5bp        linkerd-proxy   6m           5Mi
web-8956b885f-nk5bp        web             1m           4Mi
web-8956b885f-x8w6d        linkerd-proxy   8m           5Mi
web-8956b885f-x8w6d        web             3m           4Mi

# recommender runs with default flags (no --pod-recommendation-min-memory-mb
# override), so 250Mi / 25m are its floors
$ kubectl -n kube-system get deploy vpa-vertical-pod-autoscaler-recommender -o jsonpath='{.spec.template.spec.containers[0].args}'
["--stderrthreshold=info","--leader-elect=true",...,"--v=4"]
```

Final state: Stage 07 running, HPA `api` at 2 replicas (`cpu: ~12%/60%`),
2 VPAs in `Off` mode, Linkerd and viz still installed.
