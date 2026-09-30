# Stage 13 — verified run (2026-09-30)

## What was built

- `runner/Dockerfile` — Ubuntu 24.04 + official `actions-runner` v2.337.0 +
  Docker CLI (`docker.io` package) + `yq` v4.54.1. Built clean:
  `docker version` (client 29.1.3), `yq` version confirmed, `runner` user
  in the `docker` group.
- `workflows/build-and-deploy.yml` — triggers on `push` to `main` with
  `paths: [app/**]`; builds `capstone-api`/`capstone-web`, pushes to
  `localhost:5000`, bumps `chart/capstone/values.yaml` via `yq`, commits
  and pushes with the built-in `GITHUB_TOKEN`.
- `scripts/sync-app-and-workflow.sh`, `run-runner.sh`, `stop-runner.sh`.

## T1 — push app/ + workflow to GitHub

`./scripts/sync-app-and-workflow.sh` → commit `53365d1`, pushed to
`git@github.com:Vishwanathms/k3s-helm-argocd-capstone.git` (`main`).
Confirmed queued on github.com's Actions tab before a runner existed.

## T2 — runner registered and online

User set repo **Settings → Actions → General → Workflow permissions** to
**Read and write**, then supplied a fresh registration token.
`RUNNER_TOKEN=<token> ./scripts/run-runner.sh` → container
`capstone-gha-runner` up, logs show:

```
√ Runner successfully added
√ Settings Saved.
Current runner version: '2.337.0'
...Listening for Jobs
...Running job: build-push-bump
```

## T3 — run verified, loop-prevention confirmed

```
2026-09-30 08:38:11Z: Job build-push-bump completed with result: Succeeded
```

- Registry: `curl http://localhost:5000/v2/capstone-api/tags/list` →
  `{"name":"capstone-api","tags":["1.0.0","53365d1"]}`; same for
  `capstone-web` — both images built and pushed with the short-SHA tag.
- Clone: new commit `743b2b2` `ci: bump capstone images to 53365d1`,
  authored by `capstone-ci-bot`, touching only
  `chart/capstone/values.yaml` (`api.image.tag` and `web.image.tag` both
  set to `53365d1`; diff also dropped a few blank lines between blocks —
  cosmetic, `yq -i` rewrites the whole file; comments were preserved).
- **Loop check:** `docker logs capstone-gha-runner | grep -c "Running job"`
  → `1`. Only one run total — the bump commit (`chart/` only) did not
  match the `paths: [app/**]` filter and did not re-trigger the workflow.

> **T1-T3 checkpoint: PASSED.** Build → registry push → chart bump →
> git push works end-to-end through a real self-hosted runner container,
> exactly once per app change.

## T4 — Argo CD deploying the new tag: PASSED (after an unrelated cluster outage was fixed)

Initially blocked: the node (`lab-g2-vm2`) hit `DiskPressure: True`
(`/` at 92-93% full, ~7-8GB free of 98GB), which taints the node
`NoSchedule`. This was a **pre-existing, cluster-wide** condition, not
caused by Stage 13 - it took down all of ArgoCD itself (every
`argocd-*` pod `Pending` or stuck in a stale `ContainerStatusUnknown`
from a restart ~2 days earlier), not just `capstone-github`.

Fixed (same session, see chat log): cleared `/var/lib/snapd/cache`
(6.9GB of stale downloaded snap packages) + apt cache + old journal
logs, taking free space from 8.1GB (92% used) to 16GB (85% used) -
enough to clear kubelet's 15%-free `imagefs` eviction threshold.
Waited out kubelet's ~5min condition-transition hysteresis, confirmed
`DiskPressure: False` and the taint gone, then deleted the stale
ArgoCD/capstone/capstone-github pods left in terminal states so fresh
ones could schedule.

**Verified after recovery:**

```
$ kubectl -n argocd get application capstone-github -o jsonpath='sync={.status.sync.status} revision={.status.sync.revision}'
sync=Synced revision=743b2b20aaa3c0fc23aa182b1ae56c95eff7cfcb   # = the CI bump commit

$ kubectl -n capstone-github get deploy api web -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'
api	localhost:5000/capstone-api:53365d1
web	localhost:5000/capstone-web:53365d1

$ curl -H "Host: capstone-github.k3s.local" http://localhost/healthz    # 200
$ curl -H "Host: capstone-github.k3s.local" http://localhost/api/hits
{"hits":3374,"pod":"api-6cf8b85db6-k5m5s","version":"1.0.0"}
```

`Application/capstone-github` shows `health: Progressing` rather than
`Healthy` - traced to `Deployment/loadgen`'s `linkerd-network-validator`
init container crash-looping (`Init:Error`). This is **unrelated to
Stage 13**: `loadgen` isn't built or deployed by this pipeline (only
`api`/`web` are), the same flakiness independently affects `loadgen` in
the original `capstone` namespace too, and it predates/survived the
disk-pressure recovery rather than being caused by it.

> **T4 checkpoint: PASSED.** A real `app/` push resulted in a new
> short-SHA tag built, pushed, deployed via Argo CD auto-sync, and
> serving live traffic (hit counter incrementing) - no manual
> `docker`/`helm`/`git` step beyond the original `git push`.

## Known limitations

- `Deployment/loadgen` in both `capstone` and `capstone-github` has a
  crash-looping `linkerd-network-validator` init container (separate,
  pre-existing Linkerd issue, not investigated as part of this stage -
  doesn't affect `api`/`web`, which is all this pipeline touches).
- `yq -i` strips blank lines between top-level blocks in
  `chart/capstone/values.yaml` on every bump (cosmetic only; all comments
  and structure otherwise intact).
- The runner registration token was pasted directly into a chat message
  by the user rather than fetched via API - it is single-use (~1h expiry)
  and was not written to any file or committed.
- Runner container currently has `--restart unless-stopped`, so it stays
  up across VM reboots unless explicitly stopped
  (`scripts/stop-runner.sh`), consuming the disk/CPU a runner+Docker CLI
  needs even when idle.
