# ex01 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
namespace `day09-scaling`. Result: **PASS** — both imperative and
declarative scaling produced the exact replica count requested.

```console
$ kubectl apply -f ex01-scaling-applications/deployment.yaml
deployment.apps/web created
service/web created
$ kubectl rollout status deployment/web -n day09-scaling --timeout=60s
deployment "web" successfully rolled out
```

## Imperative: `kubectl scale`

```console
$ kubectl scale deployment/web -n day09-scaling --replicas=5
deployment.apps/web scaled

$ kubectl get pods -l app=web -n day09-scaling
NAME                  READY   STATUS    RESTARTS   AGE
web-67b6bfd94-nhprr   1/1     Running   0          6s
web-67b6bfd94-skj6p   1/1     Running   0          3s
web-67b6bfd94-wsw85   1/1     Running   0          3s
web-67b6bfd94-z7jzh   1/1     Running   0          6s
web-67b6bfd94-zl82r   1/1     Running   0          3s
```

Five replicas, each requesting `cpu: 50m, memory: 32Mi` — at this replica
count that's `250m` CPU and `160Mi` memory reserved from the node's
allocatable pool, before any HPA (`ex02`) or capacity math (`ex05`) enters
the picture.

## Declarative: patch `replicas:` directly

```console
$ kubectl patch deployment web -n day09-scaling -p '{"spec":{"replicas":2}}'
deployment.apps/web patched

$ kubectl get pods -l app=web -n day09-scaling
NAME                  READY   STATUS    RESTARTS   AGE
web-67b6bfd94-nhprr   1/1     Running   0          10s
web-67b6bfd94-z7jzh   1/1     Running   0          10s
```

The Deployment converged from 5 back to 2 replicas — the same
reconciliation loop that recreates a crashed Pod (Day 01/07) also removes
excess ones when the desired count drops. `kubectl scale` and editing
`replicas:` in the manifest do the exact same thing to the API object; the
only difference is which tool typed the number.
