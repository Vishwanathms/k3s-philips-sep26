# Capstone — a 3-tier app on k3s, grown one day at a time

From **Day 07 to Day 14**, every day ends by applying that day's topic to
**one app you keep for the rest of the course**:

```
Browser ──► Traefik Ingress  capstone.k3s.local
               │
               ▼
        ┌─────────────┐  /           static page
        │ web (nginx) │  /healthz    nginx's own health
        │  2 replicas │  /api/*  ──┐ proxy to the api Service
        └─────────────┘            ▼
                           ┌──────────────┐  /api/hits   INCR the counter
                           │ api (python) │  /healthz    liveness  (no redis)
                           │  2 replicas  │  /ready      readiness (pings redis)
                           └──────────────┘
                                   │ 6379
                                   ▼
                           ┌──────────────┐
                           │ redis        │  StatefulSet + 1Gi PVC (local-path)
                           │  1 replica   │  appendonly: the counter survives restarts
                           └──────────────┘
```

The proof that everything works is the **hit counter** on the front page. It
must keep counting through restarts, outages, restores and upgrades.

Every day has two parts:

- **Part A (concept):** learn the mechanism on plain **nginx**.
- **Part B (capstone):** apply it to the 3-tier app.

## What's here

| Path | What |
|---|---|
| [app/api/](app/api/) | Python API source (`app.py`), `requirements.txt`, `Dockerfile` |
| [app/web/](app/web/) | nginx config template, static page, `Dockerfile` |
| `stage-NN-*/manifests/` | the **complete** app as it stands at the end of day NN (`kubectl apply -k`) |
| `stage-NN-*/LAB-MANUAL.md` | that day's Part A + Part B steps, with checkpoints |
| `stage-NN-*/OUTPUT.md` | a verified run on the reference cluster |

## Stages

| Day | Stage | Adds to the app |
|---|---|---|
| 07 | [stage-07-build-deploy-health](stage-07-build-deploy-health/LAB-MANUAL.md) | **build + push the images**, deploy all 3 tiers, probes per tier, requests/limits, LimitRange + ResourceQuota, Guaranteed QoS for redis |
| 08 | *(planned)* | PodDisruptionBudgets; back up, delete and restore the namespace with the counter preserved |
| 09 | *(planned)* | HPA on `api`, driven by `/api/cpu` load through the Ingress |
| 10 | *(planned)* | PriorityClass for redis, preferred anti-affinity |
| 11 | *(planned)* | ServiceAccounts, NetworkPolicies (web→api→redis only), PSA `restricted`, redis password |
| 12 | *(planned)* | fault-injection script: find and fix 5 breakages |
| 13 | *(planned)* | the app as one Helm chart in your GitLab repo; images in Harbor |
| 14 | *(planned)* | Argo CD deploys it from git, self-heals drift; final acceptance checklist |

Design and decisions: [DOC/PHASE_17_CAPSTONE_PLAN.md](../DOC/PHASE_17_CAPSTONE_PLAN.md).

## Missed a day? Catch up in one command

Each stage's `manifests/` folder is the full app, not a diff:

```bash
kubectl apply -k CAPSTONE/stage-NN-<name>/manifests/
```

It's safe to run over an earlier stage: the redis PVC and the counter are kept.

## Images

| Image | Built from | Runs as |
|---|---|---|
| `localhost:5000/capstone-api:1.0.0` | [app/api/Dockerfile](app/api/Dockerfile) | UID 10001, port 8000 |
| `localhost:5000/capstone-web:1.0.0` | [app/web/Dockerfile](app/web/Dockerfile) | UID 101, port 8080 |
| `redis:7-alpine` | Docker Hub official | redis |

Each student runs a **local registry** on their own VM (`registry:2` on
`127.0.0.1:5000`, stage 07 step B4), and k3s pulls from it with no extra
configuration. The registry is set in one place per stage:
`manifests/kustomization.yaml` → `images:` → `newName`. Day 13 moves the
images to Harbor by changing only those lines.

**Prefer a real registry?** [LAB-MANUAL-Docker-Hub.md](LAB-MANUAL-Docker-Hub.md)
walks through creating a Docker Hub ID and access token, logging in, building
both apps, pushing them, and repointing those same `newName:` lines at your own
namespace — including the `imagePullSecret` a private repository needs. It
replaces stage 07's step B4 and works with any stage.
