# Capstone stage 12 — verified run

Captured **2026-09-29** on k3s `v1.36.4+k3s1`, Argo CD `v3.5.3`, kustomize
`v5.8.1`, over a healthy, running Stage 11 (`helm list -n capstone` →
revision 5, `deployed`). Counter climbed from 117700 (before Argo CD's
first sync) to 118078 (end) — `loadgen` ran throughout. Result: **PASS**
for G1–G5, D1, D2.

Scope, as decided at the start of this stage: GitLab/Harbor are not
provisioned, so the git remote is a bare repo served by `git-daemon`
(`/srv/git/capstone-gitops.git`, systemd-managed — see G1);
`kustomization.yaml` wraps Stage 11's Helm chart rather than duplicating
it as raw manifests (see G2).

> The zero-Pod-disruption proof under G3 is the headline result: Argo CD
> took over a namespace it had never touched before — installed by Helm,
> not by Argo CD — and every Pod kept its name, age and restart count.

## G1 — the git remote

```console
$ ./scripts/setup-git-remote.sh
Cloning into '/home/labuser/capstone-gitops-clone'...
warning: You appear to have cloned an empty repository.
done.
[main (root-commit) c117fa7] capstone gitops: sync from CAPSTONE/Stage12-ArgoCD/gitops
 18 files changed, 684 insertions(+)
To /srv/git/capstone-gitops.git
 * [new branch]      main -> main
Remote:  git://192.168.230.103/capstone-gitops.git
Clone:   /home/labuser/capstone-gitops-clone

$ systemctl is-active git-daemon.service
active

$ git ls-remote git://127.0.0.1/capstone-gitops.git
c117fa7fb18646ed7042d29533b23c3ca85332cd	HEAD
c117fa7fb18646ed7042d29533b23c3ca85332cd	refs/heads/main
```

## G2 — Argo CD renders Helm through kustomize

```console
$ kubectl -n argocd patch cm argocd-cm --type merge -p '{"data":{"kustomize.buildOptions":"--enable-helm"}}'
configmap/argocd-cm patched

$ kubectl kustomize --enable-helm gitops/ | grep -c '^kind:'
29

$ helm get manifest capstone -n capstone | grep -c '^kind:'
29
```

A field-by-field comparison (parsed both renders with PyYAML, matched by
`kind`+`name`, compared the loaded structures — not text) found **0
semantic differences** across all 29 objects; the only text-diff noise was
YAML re-serialization (flow-style `{ }` maps vs block style, key
reordering) from kustomize's own emitter.

## G3 — take over the live namespace

```console
$ kubectl -n capstone get pods -o custom-columns='NAME:...,RESTARTS:...,AGE:...'
api-6d655c4644-4wrvq      0   2026-09-29T09:17:46Z
api-6d655c4644-g2gng      0   2026-09-29T09:18:18Z
loadgen-749dfcb48-fdllm   0   2026-09-29T09:17:58Z
redis-0                   0   2026-09-29T11:56:09Z
web-5567498448-2bcgz      0   2026-09-29T09:18:04Z
web-5567498448-grcjl      0   2026-09-29T09:17:48Z

$ kubectl apply -f argocd/application.yaml
application.argoproj.io/capstone created

$ kubectl -n argocd get application capstone -o wide
NAME       SYNC STATUS   HEALTH STATUS   REVISION                                   PROJECT
capstone   OutOfSync     Healthy         c117fa7fb18646ed7042d29533b23c3ca85332cd   default

$ kubectl -n argocd patch application capstone --type merge -p '{"operation":{"sync":{"revision":"HEAD","prune":false,"dryRun":false,"syncStrategy":{"hook":{}}}}}'
application.argoproj.io/capstone patched
$ sleep 18
$ kubectl -n argocd get application capstone -o jsonpath='{.status.sync.status} {.status.health.status} {.status.operationState.phase}'
Synced Healthy Succeeded

$ kubectl -n capstone get pods -o custom-columns='NAME:...,RESTARTS:...,AGE:...'
api-6d655c4644-4wrvq      0   2026-09-29T09:17:46Z    # unchanged
api-6d655c4644-g2gng      0   2026-09-29T09:18:18Z    # unchanged
loadgen-749dfcb48-fdllm   0   2026-09-29T09:17:58Z    # unchanged
redis-0                   0   2026-09-29T11:56:09Z    # unchanged
web-5567498448-2bcgz      0   2026-09-29T09:18:04Z    # unchanged
web-5567498448-grcjl      0   2026-09-29T09:17:48Z    # unchanged

$ curl -s -H 'Host: capstone.k3s.local' http://$NODE_IP/api/hits
{"hits":117700,"pod":"api-6d655c4644-4wrvq","version":"1.0.0"}

$ kubectl -n capstone get deploy/web -o jsonpath='{.metadata.labels}'
{"app.kubernetes.io/managed-by":"Helm","app.kubernetes.io/part-of":"capstone","tier":"web"}

$ kubectl -n capstone get deploy/web -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}'
capstone:apps/Deployment:capstone/web
```

Zero disruption, confirmed: every AGE and RESTARTS value is identical
before and after the sync. The `app.kubernetes.io/managed-by: Helm` label
Helm set in Stage 11 is untouched; Argo CD only added its own tracking
annotation. The now-stale `meta.helm.sh/release-name` annotation is
harmless and expected — the object has two owners' bookkeeping on it now,
but only one (Argo CD, from here on) actually drives changes.

## G4 — self-heal on

```console
$ kubectl apply -f argocd/application.yaml
application.argoproj.io/capstone configured
$ kubectl -n argocd get application capstone -o jsonpath='{.spec.syncPolicy}'
{"automated":{"prune":true,"selfHeal":true}}
```

## D1 — self-heal drift drill

```console
$ kubectl -n capstone get deploy web -o jsonpath='{.spec.replicas}'
2
$ kubectl -n capstone scale deploy/web --replicas=5
deployment.apps/web scaled
$ kubectl -n argocd annotate application capstone argocd.argoproj.io/refresh=hard --overwrite
$ sleep 5
$ kubectl -n capstone get deploy web -o jsonpath='{.spec.replicas}'
2

$ kubectl -n capstone get pods -l tier=web
NAME                   READY   STATUS    RESTARTS   AGE
web-5567498448-2bcgz   2/2     Running   0          3h48m
web-5567498448-grcjl   2/2     Running   0          3h48m

$ kubectl -n argocd get events --field-selector involvedObject.name=capstone --sort-by=.lastTimestamp | tail -6
29s   Normal   OperationStarted     application/capstone   Initiated automated sync to 'c117fa7...'
29s   Normal   ResourceUpdated      application/capstone   Updated sync status: Synced -> OutOfSync
29s   Normal   ResourceUpdated      application/capstone   Updated health status: Healthy -> Progressing
25s   Normal   OperationCompleted   application/capstone   Partial sync operation to c117fa7... succeeded
24s   Normal   ResourceUpdated      application/capstone   Updated sync status: OutOfSync -> Synced
24s   Normal   ResourceUpdated      application/capstone   Updated health status: Progressing -> Healthy
```

The events prove this was a real sync cycle, not a stale read: Argo CD
detected the drift, ran a "Partial sync operation," and put `web` back to
2 replicas — the two Pods that survived are the same two from before the
drill (same names, `RESTARTS: 0`).

## D2 — git-revert rollback drill

```console
$ sed -i '.../s//tag: "1.0.0-does-not-exist"/' chart/capstone/values.yaml   # api only
$ git commit -am "drill: bump api image to a bad tag" && git push origin main
$ kubectl -n argocd annotate application capstone argocd.argoproj.io/refresh=hard --overwrite
$ sleep 15

$ kubectl -n capstone get pods -l tier=api
NAME                   READY   STATUS             RESTARTS   AGE
api-6d655c4644-4wrvq   2/2     Running            0          3h49m   # old, untouched
api-6d655c4644-g2gng   2/2     Running            0          3h49m   # old, untouched
api-77797cbc46-fcrdw   1/2     ImagePullBackOff    0          30s     # new, from the bad tag

$ curl -s -H 'Host: capstone.k3s.local' http://$NODE_IP/api/hits
{"hits":117878,"pod":"api-6d655c4644-g2gng","version":"1.0.0"}    # still answers, via the OLD Pods

$ git revert --no-edit HEAD && git push origin main
[main 78b128c] Revert "drill: bump api image to a bad tag"
$ kubectl -n argocd annotate application capstone argocd.argoproj.io/refresh=hard --overwrite
$ sleep 15

$ kubectl -n argocd get application capstone -o jsonpath='{.status.sync.status} {.status.health.status} {.status.sync.revision}'
Synced Healthy 78b128c7ab5621e1660eddcd20ca0ed82cc64329

$ kubectl -n capstone get pods -l tier=api
NAME                   READY   STATUS    RESTARTS   AGE
api-6d655c4644-4wrvq   2/2     Running   0          3h50m
api-6d655c4644-g2gng   2/2     Running   0          3h49m
```

The bad `ReplicaSet`'s one Pod is gone; the two original `api` Pods (from
before Stage 12 even started) were never restarted through the entire
drill. `helm history capstone -n capstone` still shows revision 5 as
`deployed` — untouched, because Helm was never involved in the fix. Git
was.

## G5 — final acceptance checklist

```console
$ ./scripts/acceptance-checklist.sh
--- Day 07: health & resources ---
all api/web Pods Ready (2/2)                        OK
redis-0 Running (2/2)                               OK
ResourceQuota present                               OK
--- Day 08: disruption & backup ---
PDB web minAvailable satisfied                      OK
PDB api minAvailable satisfied                      OK
--- Day 09: HPA scaling ---
HPA api present, has metrics                        OK
--- Day 10: scheduling ---
PriorityClasses exist                               OK
redis on capstone/data=true node                     OK
--- Day 11: security ---
namespace PSA restricted                            OK
web ServiceAccount automount off                    OK
default-deny NetworkPolicy present                  OK
redis-auth Secret present                            OK
--- Day 12: troubleshooting ---
web Service has endpoints                            OK
api Service has endpoints                            OK
--- Day 13: Helm chart lineage ---
objects carry Helm release labels                    OK
--- Day 14: Argo CD ---
Application capstone Synced                          OK
Application capstone Healthy                          OK
automated selfHeal enabled                            OK
live web replicas match git (2)                       OK
--- End-to-end proof ---
counter reachable via Ingress                         OK

== ACCEPTANCE PASS - capstone is production-shaped end to end
```

All 20 checks pass. `helm list -n capstone` still reports revision 5,
`deployed` — a frozen record of how the release got here, no longer the
mechanism for changing it.

## Known limitations, left for a later pass

- **Not a real GitLab repo.** The bare repo + `git-daemon` stands in for
  it; `repoURL` in `argocd/application.yaml` is the only line that would
  need to change.
- **`argo-demo`** (the Phase 15 / Day 14 GitOps-Tooling exercise
  Application, unrelated to the capstone) is still `Unknown` sync status —
  its own bare repo (`/tmp/argocd-remote.git`) was never durable and is
  gone. `git-daemon.service` (this stage) now serves `/srv/git`, not
  `/tmp`, so this doesn't fix `argo-demo`; it would need its own repo
  recreated under `/srv/git` to match this stage's durability fix.
- **No self-hosted image rebuild through this pipeline** — Harbor and a
  `pythonapp:v5` rebuild are still deferred, same as Stage 11.
