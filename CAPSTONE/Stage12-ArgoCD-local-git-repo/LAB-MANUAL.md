# Capstone stage 12 — Argo CD deploys it from git (Day 14)

## Scenario

Since Stage 11 the capstone has been a real Helm release, but *you* still
run `helm upgrade` by hand from your laptop. Today that stops: **Argo CD**
takes over. From here, the only way to change the running app is to change
a file in git and push it — Argo CD notices, renders it, and applies it.
Change something by hand instead (`kubectl scale`, a stray `kubectl edit`)
and Argo CD puts it back within seconds. A bad release isn't fixed with
`helm rollback` any more — it's fixed with `git revert`.

**Scope decision (documented in `task.md`):** GitLab and Harbor are still
not provisioned as VMs (Stage 11 deferred them too). Instead of "the
student's GitLab repo," this stage uses a small **bare git repo served by
`git-daemon`** on this same VM, as a stand-in with the same git-push
workflow. Swapping it for a real GitLab repo later is a one-line change
(`repoURL` in `argocd/application.yaml`) — nothing else in this lab depends
on which git server it is.

**Second scope decision:** the plan originally called for introducing
`kustomization.yaml` at this stage, written before Stage 11 existed. Since
Stage 11 already turned the whole app into one Helm chart, this stage adds
a **thin `kustomization.yaml` that wraps that chart** (`kustomize build
--enable-helm`) rather than duplicating it as raw manifests. Both plan
items are satisfied; nothing is maintained twice.

## What changed since Stage 11

| File | Change |
|---|---|
| `gitops/chart/` | **copy** of Stage 11's `chart/capstone/`, unchanged — this is what git now ships |
| `gitops/kustomization.yaml` | **new**: wraps the chart so Argo CD's kustomize engine renders it (`helmGlobals.chartHome` + `helmCharts`) |
| `argocd/application.yaml` | **new**: the Argo CD `Application` — repo, path, destination, `syncPolicy.automated` |
| `scripts/setup-git-remote.sh` | **new, one-time**: creates the bare repo + `git-daemon` systemd unit, clones it to `~/capstone-gitops-clone`, pushes the initial content |
| `scripts/acceptance-checklist.sh` | **new**: one check per day, Day 07 through Day 14 |
| `drills/self-heal-drift.sh` | **new**: manual `kubectl scale` drift, reverted by Argo CD |
| `drills/git-rollback.sh` | **new**: a bad release shipped and rolled back through git, not Helm |

`Stage11-Helm/chart/` isn't touched — it's kept as the record of how the
chart was first built and adopted.

## Learning objectives

- explain why a `kustomization.yaml` with no `resources:`, only
  `helmCharts:`, is a legitimate (if unusual) way to deploy a chart through
  Argo CD
- take over a **live, Helm-managed** namespace with Argo CD and prove zero
  Pod disruption, the same way Stage 11 proved zero disruption adopting
  `kubectl`-applied objects into Helm
- distinguish `OutOfSync` (git and cluster disagree) from `Degraded`
  (cluster matches git, but git was wrong)
- explain what `syncPolicy.automated.selfHeal` actually watches, and why it
  reacts in seconds, not on the next `git push`
- perform a rollback with `git revert` and explain why `helm rollback`
  is no longer the right tool once Argo CD owns the release

## Before starting

Stage 11 running, healthy:

```bash
cd ~/Documents/k3s-training/CAPSTONE/Stage12-ArgoCD
export NODE_IP=$(hostname -I | awk '{print $1}')
kubectl -n capstone get pods                 # 6 Pods, all Running
helm list -n capstone                        # STATUS deployed
curl -s -H 'Host: capstone.k3s.local' http://$NODE_IP/api/hits; echo
kubectl -n argocd get pods                   # all Running - if not, see the setup manual below
```

**Argo CD not installed yet?** Follow
[../Stage12-GitHub-argocd/LAB-MANUAL-ArgoCD-Setup.md](../Stage12-GitHub-argocd/LAB-MANUAL-ArgoCD-Setup.md)
first — it installs Argo CD, exposes the UI through Traefik and secures the
admin account. It also performs this stage's step G2 (`--enable-helm`), so if
you used it you can read G2 and move on.

---

## G1 — the git remote (5 min)

There's no GitLab VM yet, so this stage stands one up the honest way: a
bare repo, served read-write over the plain `git://` protocol by
`git-daemon`, running as a systemd service so it survives a reboot (the
Day 14 GitOps-Tooling exercises' bare repo lived in `/tmp` and didn't).

```bash
./scripts/setup-git-remote.sh
```

This creates `/srv/git/capstone-gitops.git`, installs+starts
`git-daemon.service`, clones it to `~/capstone-gitops-clone`, and pushes
this stage's `gitops/` folder (the chart + `kustomization.yaml`) as the
first commit.

> **Checkpoint G1:** `git ls-remote git://$NODE_IP/capstone-gitops.git`
> lists a `refs/heads/main`. `systemctl is-active git-daemon` prints
> `active`.

## G2 — teach Argo CD to render Helm through kustomize (2 min)

By default Argo CD's kustomize engine runs with the Helm inflator
**disabled** (a security default — inline `helmCharts:` can shell out to
`helm`). Turn it on cluster-wide:

```bash
kubectl -n argocd patch cm argocd-cm --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-helm"}}'
```

You can prove the render works **before** Argo CD ever sees it:

```bash
kubectl kustomize --enable-helm gitops/ | grep -c '^kind:'    # 29
```

> **Checkpoint G2:** the local render also produces exactly 29 objects —
> the same count as `helm get manifest capstone -n capstone` from Stage 11.

## G3 — take over the live namespace, prove zero disruption (10 min)

This is the same move as Stage 11's `adopt-into-helm.sh`, in reverse: a
namespace that's already correctly deployed (by Helm) is being handed to a
*different* tool (Argo CD). Record the baseline first:

```bash
kubectl -n capstone get pods \
  -o custom-columns='NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp'
```

Apply the `Application` with **manual** sync first — don't let it touch
anything automatically yet:

```bash
kubectl apply -f argocd/application.yaml
kubectl -n argocd get application capstone     # SYNC STATUS: OutOfSync, HEALTH: Healthy
```

`OutOfSync` here doesn't mean the cluster is wrong — it means these objects
have never been synced *by this Application* before, so Argo CD hasn't
taken tracking ownership of them yet. Trigger a real sync and compare pod
identities again:

```bash
kubectl -n argocd patch application capstone --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD","prune":false,"dryRun":false,"syncStrategy":{"hook":{}}}}}'
sleep 10
kubectl -n argocd get application capstone     # Synced, Healthy
kubectl -n capstone get pods \
  -o custom-columns='NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp'
```

> **Checkpoint G3:** every Pod name, age and restart count from the
> baseline is unchanged. Argo CD added an `argocd.argoproj.io/tracking-id`
> annotation to each object and left the Helm-owned `app.kubernetes.io/
> managed-by: Helm` label in place — it took over *tracking*, not
> ownership of the objects' history.

## G4 — turn on self-heal (2 min)

```bash
kubectl apply -f argocd/application.yaml   # syncPolicy.automated: {prune: true, selfHeal: true}
```

From this point: **stop running `helm upgrade` or `kubectl edit` against
`capstone`.** Every change goes through
`~/capstone-gitops-clone` + `git push` from here on.

> **Checkpoint G4:** `kubectl -n argocd get application capstone -o
> jsonpath='{.spec.syncPolicy.automated}'` shows
> `{"prune":true,"selfHeal":true}`.

## D1 — drill: manual drift gets reverted (5 min)

```bash
./drills/self-heal-drift.sh
```

Scales `web` to 5 replicas by hand, forces an Argo CD refresh (so the
drill doesn't wait out the default 3-minute poll), then shows `web` back
at 2. Check the `Application`'s events for the real story:

```bash
kubectl -n argocd get events --field-selector involvedObject.name=capstone --sort-by=.lastTimestamp | tail -10
```

> **Checkpoint D1:** the events show a genuine `OperationStarted` →
> `OperationCompleted` sync cycle right after the drift — this isn't a
> no-op, Argo CD actually re-applied the Deployment.

## D2 — drill: a bad release, rolled back with `git revert` (10 min)

```bash
./drills/git-rollback.sh
```

Walks through: bump `api`'s image tag to one that was never pushed to the
registry → commit → push → Argo CD syncs it (a new `ReplicaSet` rolls out,
the **old** Pods stay up because the new ones never go Ready) →
`ImagePullBackOff` → the counter still answers through the old Pods →
`git revert` → push → Argo CD syncs the revert → recovered.

> **Checkpoint D2:** at no point does `/api/hits` stop answering, and the
> original `api` Pods (from before the drill) are never restarted — only
> the doomed new `ReplicaSet`'s Pod is ever unhealthy.

## G5 — final acceptance checklist (5 min)

One check per day, 07 through 14:

```bash
./scripts/acceptance-checklist.sh
```

> **Checkpoint G5:** `ACCEPTANCE PASS` — every check green, on the same
> namespace that's been running continuously since Stage 07.

## Cleanup

None by default — this is the last stage; `capstone` stays running,
Argo CD stays the source of truth.

To go back to unmanaged `helm upgrade` (not recommended, breaks the
lesson): `kubectl delete -f argocd/application.yaml` removes the
`Application` without touching the live objects (no `prune` runs on
delete by default).
