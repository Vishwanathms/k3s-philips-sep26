# Capstone stage 13 — GitHub Actions CI, self-hosted runner, GitOps bump

## Scenario

Every earlier stage that changed the app's image had a human run
`docker build` / `docker push` / edit `values.yaml` by hand. This stage
automates that: a GitHub Actions workflow, running on a **self-hosted
runner container on this VM**, builds `capstone-api` and `capstone-web`
from `app/`, pushes them to the Stage00 local registry, bumps
`chart/capstone/values.yaml`'s image tags, and pushes that commit back —
which the Stage12-GitHub-argocd `Application` then syncs automatically.

**Why the runner has to be self-hosted, not GitHub-hosted:** a
GitHub-hosted runner is a VM in GitHub's cloud. It cannot reach
`localhost:5000` on this training VM — the registry from Stage00 is
deliberately bound to `127.0.0.1` only, not published on the network. A
runner has to run *on this VM* for `docker push localhost:5000/...` to
mean anything.

**Why it needs `app/**` as the only trigger path:** the workflow's own
last step commits a change to `chart/capstone/values.yaml`. If the
workflow triggered on every push to the repo, that commit would trigger
another run, which would commit again, forever. Restricting the trigger to
`paths: [app/**]` means the chart-bump commit (which touches
`chart/capstone/values.yaml`, not `app/`) never matches the filter and
never re-fires the workflow.

## What's here

| Path | What |
|---|---|
| `runner/Dockerfile` | self-hosted runner image: Ubuntu + official `actions-runner` tarball + Docker CLI + `yq` |
| `runner/entrypoint.sh` | registers the runner on first start (`config.sh`), then `run.sh`; skips re-registration if `/home/runner` (a named volume) already has `.runner` |
| `workflows/build-and-deploy.yml` | the workflow itself — synced into the GitHub repo's `.github/workflows/` |
| `scripts/sync-app-and-workflow.sh` | adds `app/` and `.github/workflows/` to the existing `~/capstone-gitops-github-clone` (from Stage12-GitHub-argocd), alongside `chart/` — without touching `chart/`, `kustomization.yaml`, or `values-github.yaml` |
| `scripts/run-runner.sh` | builds the runner image and (re)starts the container |
| `scripts/stop-runner.sh` | removes the runner container + its persisted volume |

## Before starting

- Stage12-GitHub-argocd done: `~/capstone-gitops-github-clone` exists,
  pushes to `git@github.com:Vishwanathms/k3s-helm-argocd-capstone.git`
  work over the SSH deploy key
- Stage00's registry running (`docker ps --filter name=capstone-registry`)
- On github.com, repo **Settings → Actions → General → Workflow
  permissions** set to **"Read and write permissions"** — the workflow's
  last step pushes a commit using the built-in `GITHUB_TOKEN`; with the
  default read-only setting that push is rejected with `403`. This is a
  one-time, one-click setting; nothing here can set it via the SSH deploy
  key (it's an API-only setting).

## T1 — push app/ and the workflow into the GitHub repo

```bash
./scripts/sync-app-and-workflow.sh
```

Adds `app/api/`, `app/web/`, and `.github/workflows/build-and-deploy.yml`
to the clone (leaving `chart/` etc. untouched) and pushes. Since this push
touches `app/**`, it is itself the first thing that will trigger the
workflow once a runner is listening — but the run will sit **Queued**
until T2.

> **Checkpoint T1:** the files are visible at
> github.com/Vishwanathms/k3s-helm-argocd-capstone; a run shows
> **Queued** under the repo's **Actions** tab.

## T2 — get a runner registration token and start the runner

On github.com: **Settings → Actions → Runners → New self-hosted runner**
→ Linux / x64. Copy the token shown under `./config.sh ... --token
<TOKEN>` (valid ~1 hour, one-time use).

```bash
RUNNER_TOKEN=<paste the token> ./scripts/run-runner.sh
```

Builds `capstone-gha-runner:local` (Ubuntu + `actions-runner` v2.337.0 +
Docker CLI + `yq`) and starts it:

- `--network host` — matches how the app itself would reach
  `localhost:5000` if built by hand on this VM
- `--group-add "$(stat -c '%g' /var/run/docker.sock)"` — lets the
  unprivileged `runner` user use the mounted socket, whatever GID the
  VM's Docker group happens to be
- `-v /var/run/docker.sock:/var/run/docker.sock` — Docker-outside-of-
  Docker: `docker build`/`push` *inside* the container are executed by
  the **VM's own** Docker daemon, the same one Stage00's registry runs in
- `-v capstone-runner-data:/home/runner` — `.runner`/`.credentials`
  persist across `docker restart`, so `RUNNER_TOKEN` is only needed again
  if this volume is removed (`stop-runner.sh` removes it deliberately)

```bash
docker logs -f capstone-gha-runner
```

Expected: `... Listening for Jobs`. The T1 run (if still queued) should
start within seconds.

> **Checkpoint T2:** the repo's **Settings → Actions → Runners** shows
> `capstone-vm-runner` as **Idle** (or **Active** while the queued job
> runs).

## T3 — watch the run, verify the loop closes and doesn't repeat

```bash
curl -s http://localhost:5000/v2/capstone-api/tags/list
curl -s http://localhost:5000/v2/capstone-web/tags/list
git -C ~/capstone-gitops-github-clone log --oneline -3
git -C ~/capstone-gitops-github-clone pull --ff-only
grep -A1 'tag:' ~/capstone-gitops-github-clone/chart/capstone/values.yaml
```

Expected: both tag lists include a new 7-char short-SHA tag; the clone's
log has a new `ci: bump capstone images to <sha>` commit; `values.yaml`
shows that same tag for both `api.image.tag` and `web.image.tag`.

On github.com's **Actions** tab, confirm there is **exactly one** run per
push — the bump commit must **not** have queued a second run (proof the
`paths: [app/**]` filter is doing its job).

> **Checkpoint T3:** one workflow run, both images pushed with a matching
> tag, `values.yaml` bumped, no second (looped) run triggered.

## T4 — prove it end-to-end: Argo CD deploys the new image

If `capstone-github`'s `Application` (Stage12-GitHub-argocd) is synced
automatically:

```bash
kubectl -n argocd get application capstone-github -o jsonpath='{.status.sync.status}{"\n"}'
kubectl -n capstone-github get deploy api web -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```

Expected: `Synced`; both `image:` lines show the same short-SHA tag as
T3.

Then make a trivial, real change under `app/` (e.g. bump
`APP_VERSION`/`WEB_VERSION` in a Dockerfile `ENV` line, or edit
`app/web/html/index.html`), commit, and push it through the *normal* repo
flow (not the CI's own clone dance) to prove a genuine app change drives
the whole pipeline. The simplest rehearsal on this VM is editing the file
straight in `~/capstone-gitops-github-clone/app/...` and pushing — the
canonical source in `CAPSTONE/app/` stays what `sync-app-and-workflow.sh`
would push next time it runs, so keep the two in sync by hand if you edit
the clone directly.

> **Checkpoint T4:** a real `app/` change results in a new tag deployed
> and visible via `kubectl`, with no manual `docker`/`helm`/`git` step
> beyond the initial `git push`.

## Day-to-day commands

| Task | Command |
|---|---|
| Is the runner up? | `docker ps --filter name=capstone-gha-runner` |
| Runner logs | `docker logs -f capstone-gha-runner` |
| Re-register (new token) | `./scripts/stop-runner.sh && RUNNER_TOKEN=<new> ./scripts/run-runner.sh` |
| What tags are in the registry? | `curl -s http://localhost:5000/v2/capstone-api/tags/list` |

## Troubleshooting

| Symptom | Likely cause / check |
|---|---|
| Workflow run stuck **Queued** forever | no runner online, or its labels don't match `runs-on: self-hosted` — `docker logs capstone-gha-runner`, confirm `Listening for Jobs` |
| `remote: Permission to ... denied` on the last step's `git push` | repo **Settings → Actions → General → Workflow permissions** is still read-only — set to "Read and write permissions" |
| `docker: permission denied` inside a job step | `--group-add` GID didn't match at container start (socket GID can change if Docker was reinstalled) — recreate: `./scripts/stop-runner.sh` then `run-runner.sh` again |
| `docker push` fails with connection refused | Stage00's `capstone-registry` container isn't running — `docker start capstone-registry` |
| A second run fires right after the bump commit | the `paths:` filter was edited or removed from `build-and-deploy.yml` — it must stay `app/**` |
| `config.sh` fails with `401`/expired token | `RUNNER_TOKEN` is >1h old — get a fresh one from Settings → Actions → Runners |

## Next

This closes the capstone's CI/CD loop: app change → build → registry →
chart bump → git push → Argo CD sync, entirely through `git push`, no
manual `docker`/`helm` step. See `CAPSTONE/README.md`'s stage table and
`DOC/PHASE_17_CAPSTONE_PLAN.md` for how this fits the rest of the days.
