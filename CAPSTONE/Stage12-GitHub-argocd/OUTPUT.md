# Capstone stage 12b — verified run

Captured **2026-09-30** on k3s `v1.36.4+k3s1`, Argo CD `v3.5.3`, against
`git@github.com:Vishwanathms/k3s-helm-argocd-capstone.git` (private).
`Stage12-ArgoCD`'s own `Application/capstone` was checked before and after
and never left `Synced`/`Healthy` — this stage is additive, not a
replacement.

## G1 — push to GitHub

```console
$ ssh -T git@github.com
Hi Vishwanathms! You've successfully authenticated, but GitHub does not provide shell access.

$ ./scripts/setup-github-remote.sh
Cloning into '/home/labuser/capstone-gitops-github-clone'...
[main 2cfc58d] capstone-github gitops: sync from CAPSTONE/Stage12-GitHub/gitops
 2 files changed, 57 insertions(+), 8 deletions(-)
 create mode 100644 values-github.yaml
To github.com:Vishwanathms/k3s-helm-argocd-capstone.git
   78b128c..2cfc58d  main -> main
```

> Note: commits `c117fa7`..`78b128c` already existed on this repo before
> this stage's own first push — a copy of `Stage12-ArgoCD`'s content and
> its drill history got pushed here by mistake mid-session, *before* the
> instruction to leave Stage12-ArgoCD untouched and build this as a
> separate stage. No harm done (this stage's own commit `2cfc58d`
> overwrote `kustomization.yaml` with the namespaced+patched version and
> added `values-github.yaml`), but the repo's git history carries those
> earlier commits. See the note at the end of this file.

## G2 — Argo CD repo credential

```console
$ ./scripts/add-argocd-repo-credential.sh
secret/capstone-github-repo-creds created
secret/capstone-github-repo-creds labeled
Argo CD repository credential created for git@github.com:Vishwanathms/k3s-helm-argocd-capstone.git
```

## Local render check (before touching the cluster)

```console
$ kubectl kustomize --enable-helm gitops/ | grep -c '^kind:'
26

$ python3 -c "... namespace name check ..."
namespace name: capstone-github

$ python3 -c "... ingress rules check ..."
[{'host': 'capstone-github.k3s.local', ...}]
```

29 objects in `Stage12-ArgoCD`, 26 here — the 3 `PriorityClass` objects
are deliberately dropped (see LAB-MANUAL "Scenario"). `priorityClassName`
references in the Deployments/StatefulSet stay in place (4 occurrences),
resolving against the PriorityClasses the original `capstone` Application
already owns.

## G3 — namespace + redis secret

```console
$ ./scripts/create-redis-secret.sh
namespace/capstone-github created
secret/redis-auth created
secret/redis-auth labeled
```

## G4 — deploy

```console
$ kubectl apply -f argocd/application.yaml
application.argoproj.io/capstone-github created

$ kubectl -n argocd get application capstone-github -o wide
NAME              SYNC STATUS   HEALTH STATUS   REVISION
capstone-github   OutOfSync     Healthy         2cfc58d55e9d234714c33c48ec33441971ddab73

$ sleep 20 && kubectl -n argocd get application capstone-github
NAME              SYNC STATUS   HEALTH STATUS
capstone-github   Synced        Healthy

$ kubectl -n capstone-github get pods
NAME                      READY   STATUS    RESTARTS   AGE
api-698f785678-kqpxv      2/2     Running   0          61s
api-698f785678-vb4r5      2/2     Running   0          78s
loadgen-749dfcb48-6gxfc   2/2     Running   0          79s
redis-0                   2/2     Running   0          78s
web-5dc986bb99-7qffr      2/2     Running   0          78s
web-5dc986bb99-jp4hc      2/2     Running   0          77s
```

Startup was noisy but expected: `Unhealthy` events on `redis-0`'s startup
probe (waiting on the Linkerd proxy's `/ready`) and `api`'s readiness
probe (waiting on redis) during the first ~20s, plus HPA's usual
`FailedGetContainerResourceMetric` until the metrics pipeline sees the new
Pods — the same warm-up noise Stage04 and Stage09 documented for the
original namespace. Everything settled to `2/2 Running` and `Healthy`
inside 30s.

## Verify: two independent apps, one cluster

```console
$ curl -s -H 'Host: capstone-github.k3s.local' http://$NODE_IP/api/hits
{"hits":46,"pod":"api-698f785678-kqpxv","version":"1.0.0"}

$ curl -s -H 'Host: capstone.k3s.local' http://$NODE_IP/api/hits
{"hits":204373,"pod":"api-6d655c4644-g2gng","version":"1.0.0"}

$ kubectl -n argocd get application capstone
NAME       SYNC STATUS   HEALTH STATUS
capstone   Synced        Healthy

$ kubectl get priorityclass capstone-data -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}'
capstone:scheduling.k8s.io/PriorityClass:capstone/capstone-data

$ kubectl get priorityclass | grep capstone
capstone-app     10000    false   39h   PreemptLowerPriority
capstone-batch   -100     false   39h   Never
capstone-data    100000   false   39h   PreemptLowerPriority
```

Two separate, independently-climbing counters. The original `capstone`
Application is exactly as it was before this stage started. The 3
`PriorityClass` objects are still tracked only by `capstone` — no
ownership fight, confirming the delete-patch approach worked as intended.

## Known limitations / notes for next time

- **Git history on the GitHub repo isn't clean** — see the G1 note above.
  Cosmetic only (private repo, no other clones), but worth a
  `git checkout --orphan` + force-push squash before using this repo in a
  live demo, if a tidy history matters for the audience.
- Same deferred items as `Stage12-ArgoCD`: no Harbor, no real image
  rebuild pipeline.
- Resource cost: this stage roughly doubles `capstone`'s footprint on the
  node (checked beforehand: node was at 15%/3% CPU/memory requests, so
  there was ample headroom — not something to assume on a smaller VM).
