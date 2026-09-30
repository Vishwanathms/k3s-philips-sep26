# Capstone stage 12b — the same Argo CD demo, sourced from real GitHub

## Scenario

`Stage12-ArgoCD-local-git-repo/` proved the whole Argo CD story — zero-disruption takeover,
self-heal, git-revert rollback — against a **local `git-daemon` repo**,
because GitLab wasn't provisioned. This stage repeats it against a **real
GitHub repository**, without touching that original demo at all: it's a
second, independent copy, running in its own namespace, from its own git
history.

**Why a second namespace, not just a new `repoURL`:** the obvious move —
just change `Stage12-ArgoCD-local-git-repo/argocd/application.yaml`'s `repoURL` — was
explicitly ruled out (keep `Stage12-ArgoCD` exactly as verified). The next
obvious move — a second Argo CD `Application` pointed at the *same*
`capstone` namespace — doesn't work: this chart's `PriorityClass` objects
are **cluster-scoped**, and the live `capstone` Application already owns
them. A second `Application` claiming the same cluster-scoped objects would
fight the first one over their tracking annotation. So this stage deploys
into `capstone-github`, and its `kustomization.yaml` **deletes the
PriorityClass objects from its own render** (`patches: ... $patch: delete`)
— the Pods still reference `priorityClassName: capstone-app` etc., which
resolve fine, because a PriorityClass is a shared, cluster-wide resource;
this stage just doesn't try to own it.

## What's here vs. `Stage12-ArgoCD-local-git-repo/`

| File | Same as Stage12-ArgoCD? | Why |
|---|---|---|
| `gitops/chart/` | **identical**, byte-for-byte copy | proves it's the same app, not a rewrite |
| `gitops/kustomization.yaml` | **different**: `namespace: capstone-github`, `additionalValuesFiles: [values-github.yaml]`, plus the 3 `PriorityClass` delete patches | see above |
| `gitops/values-github.yaml` | **new**: overrides only `ingress.host` (`capstone-github.k3s.local`) | a second Ingress can't claim the same host as the first |
| `argocd/application.yaml` | **different**: `name: capstone-github`, `repoURL` is the real GitHub SSH URL, `destination.namespace: capstone-github` | separate Application, separate namespace |
| `scripts/setup-github-remote.sh` | **new** | pushes to `git@github.com:Vishwanathms/k3s-helm-argocd-capstone.git` via SSH deploy key, into its own clone `~/capstone-gitops-github-clone` |
| `scripts/add-argocd-repo-credential.sh` | **new** | Argo CD needs its own credential for a *private* repo — a Secret in `argocd` ns, `--from-file=sshPrivateKey` straight off disk, never printed |
| `scripts/create-redis-secret.sh` | **new** | `capstone-github` namespace needs its own `redis-auth` Secret (chart's `existingSecret` is looked up per-namespace) |

## Before starting

- **Argo CD installed and ready** — see
  [LAB-MANUAL-ArgoCD-Setup.md](LAB-MANUAL-ArgoCD-Setup.md) if this is a fresh
  cluster. That manual's step A9 (`kustomize.buildOptions: --enable-helm`) is
  **required** here: this stage's repo is a kustomization wrapping a Helm
  chart, and without it the Application syncs to an empty render.
- `Stage12-ArgoCD` running, healthy, **untouched** — this stage doesn't
  read or write anything under `Stage12-ArgoCD-local-git-repo/`
- A GitHub repo, **private**, created empty (no README/gitignore)
- This VM's SSH key (`~/.ssh/id_rsa.pub`) added to that repo as a **Deploy
  key with write access** (Settings → Deploy keys)

```bash
cd ~/Documents/k3s-training/CAPSTONE/Stage12-GitHub
ssh -T git@github.com   # "Hi <you>! ... successfully authenticated"

kubectl -n argocd get pods                                        # all Running
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.kustomize\.buildOptions}{"\n"}'   # --enable-helm
```

---

## G1 — push the chart to GitHub

```bash
./scripts/setup-github-remote.sh
```

Clones (or initializes) `~/capstone-gitops-github-clone`, copies this
stage's `gitops/` into it, commits, pushes over SSH.

> **Checkpoint G1:** `git -C ~/capstone-gitops-github-clone log --oneline
> -1` shows the sync commit; the same commit is visible on
> github.com/Vishwanathms/k3s-helm-argocd-capstone.

## G2 — give Argo CD a credential for the private repo

```bash
./scripts/add-argocd-repo-credential.sh
```

Creates `Secret/capstone-github-repo-creds` in the `argocd` namespace
(`argocd.argoproj.io/secret-type: repository`), holding the same SSH key —
read straight from `~/.ssh/id_rsa`, never echoed anywhere.

> **Checkpoint G2:** `kubectl -n argocd get secret
> capstone-github-repo-creds -o jsonpath='{.metadata.labels}'` shows
> `argocd.argoproj.io/secret-type: repository`.

## G3 — the namespace and its redis password

```bash
./scripts/create-redis-secret.sh
```

Creates `capstone-github` (if Argo CD hasn't already) and its
`redis-auth` Secret, the same way Stage09 did for `capstone`.

## G4 — deploy

```bash
kubectl apply -f argocd/application.yaml
kubectl -n argocd get application capstone-github -o wide
```

Automated sync is on from the start here (unlike Stage12-ArgoCD's
deliberately cautious manual-first adoption) — there's nothing live to
adopt; this is a clean install into an empty namespace.

> **Checkpoint G4:** within ~30s, `SYNC STATUS: Synced`, `HEALTH STATUS:
> Healthy`, and `kubectl -n capstone-github get pods` shows 6 Pods
> `2/2 Running`.

## Verify: independence from the original demo

```bash
curl -s -H 'Host: capstone-github.k3s.local' http://$(hostname -I | awk '{print $1}')/api/hits; echo
curl -s -H 'Host: capstone.k3s.local' http://$(hostname -I | awk '{print $1}')/api/hits; echo
kubectl get priorityclass capstone-data -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}'; echo
```

> **Checkpoint:** two different counters, both climbing independently; the
> `PriorityClass` is still tracked by `capstone` (the original Application),
> not `capstone-github` — no ownership fight happened.

The same self-heal and git-revert drills from `Stage12-ArgoCD-local-git-repo/drills/`
apply here unchanged — just `git commit`/`git push` inside
`~/capstone-gitops-github-clone` instead, and watch
`Application/capstone-github`.

## Cleanup

```bash
kubectl delete -f argocd/application.yaml   # Application only, no prune on delete
kubectl delete namespace capstone-github    # the actual teardown
kubectl -n argocd delete secret capstone-github-repo-creds
```
