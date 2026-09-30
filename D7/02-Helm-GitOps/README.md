# Day 13 — Helm & GitOps

Module 9 — Package Management & GitOps.

Builds directly on:

- **Day 01–12:** every chart installed today deploys the same kinds of
  objects (Deployments, Services, Secrets) earlier days already built by
  hand — Helm's job is templating and lifecycle management on top of
  exactly that, not a new deployment model.

This module covers every topic on the list — Helm Architecture, Charts,
Repositories, Values, Templates, Dependencies, Releases, Rollback,
Upgrade, Best Practices — as real, hands-on labs, plus a GitOps workflow
lab (the day's title, though not itemized in the topic list) built as a
real git-driven reconciliation loop rather than a full ArgoCD/Flux install
— see the scope note below.

| Material | Purpose |
|---|---|
| [slides/PPT_CONTENT.md](slides/PPT_CONTENT.md) | Detailed slide-by-slide teaching content, presenter cues, and sources |
| [slides/Day-13-Helm-GitOps.pptx](slides/Day-13-Helm-GitOps.pptx) | Presentation-ready PowerPoint deck |

## Hands-on labs

| # | Lab | Proves | Verified run |
|---|-----|--------|--------------|
| 1 | [ex01-helm-architecture](ex01-helm-architecture/) | Helm v3 is client-only (no Tiller); a release IS a real Kubernetes Secret, decoded and inspected directly | [OUTPUT.md](ex01-helm-architecture/OUTPUT.md) |
| 2 | [ex02-charts-and-values](ex02-charts-and-values/) | real chart anatomy (`helm create`); values precedence (`values.yaml` < `-f` < `--set`) proved with real pod counts | [OUTPUT.md](ex02-charts-and-values/OUTPUT.md) |
| 3 | [ex03-templates-deep-dive](ex03-templates-deep-dive/) | `helm template` needs zero cluster access (proved with a bogus kubeconfig); `required` is a real hard-fail render guard | [OUTPUT.md](ex03-templates-deep-dive/OUTPUT.md) |
| 4 | [ex04-dependencies](ex04-dependencies/) | a real local subchart + a real remote (OCI-backed) subchart, with real values namespacing | [OUTPUT.md](ex04-dependencies/OUTPUT.md) |
| 5 | [ex05-releases-upgrade-rollback](ex05-releases-upgrade-rollback/) | rollback creates a NEW revision, it doesn't rewind the pointer — proved via real revision history | [OUTPUT.md](ex05-releases-upgrade-rollback/OUTPUT.md) |
| 6 | [ex06-best-practices](ex06-best-practices/) | `helm lint` catches far less than expected (proved empirically); `--atomic` really auto-rolls-back a failed upgrade | [OUTPUT.md](ex06-best-practices/OUTPUT.md) |
| 7 | [ex07-gitops-workflow](ex07-gitops-workflow/) | a real git-driven reconciler that deploys, updates, AND corrects manual drift back to git's declared state | [OUTPUT.md](ex07-gitops-workflow/OUTPUT.md) |

Start with [LAB-MANUAL.md](LAB-MANUAL.md). All seven hands-on labs were run
for real against this cluster on **2026-09-16** — every lab's own
`OUTPUT.md` has the full captured transcript.

```bash
helm list -A | grep day13   # check for anything left running
kubectl delete namespace day13-helm-gitops   # fast cleanup for lab objects
```

## What this day needed that earlier days didn't

**The day's title says "GitOps" but the topic list only itemizes Helm
subtopics** — ex07 was built as a genuine, evidence-based scope call: this
node was already at **62% real memory usage** (`kubectl top node`) from
this day's own other real releases before ex07 even started, and a full
ArgoCD/Flux install typically adds 6-8 more Pods. Rather than skip GitOps
entirely or risk the shared cluster's headroom, ex07 builds the **actual
mechanism** those tools automate — a real local git repo as source of
truth plus a real `git pull` + `helm upgrade --install --atomic`
reconciler — and proves the core GitOps principle (drift correction: a
manual `kubectl scale` was silently reverted on the next reconciliation
tick) at a fraction of the resource cost.

**`helm lint` was shown to catch far less than most people assume** —
ex06 built a real anti-pattern chart (hardcoded resource names, hardcoded
namespace, no labels, floating tags, no resource limits) that `helm lint`
passed cleanly, then proved the real, concrete consequences (a namespace
silently ignored, a second install failing outright, genuinely unbounded
resources) empirically rather than just asserting the risk.

**Bitnami's 2025 distribution changes surfaced twice, independently** —
ex01 hit their new limited-free-tier image warning, and ex04 found their
`https://charts.bitnami.com/bitnami` HTTP repo now resolves chart
downloads to an OCI registry (`registry-1.docker.io/bitnamicharts/...`)
rather than a plain `.tgz` URL.

## Capstone stage 11

After the labs above, students convert the course capstone into one Helm
chart — scoped to exactly what this day teaches: packaging, upgrade and
rollback. The app has been running since Stage 02 via plain `kubectl
apply`, so the real first step is **adopting** those existing objects into
a release (Helm refuses to install over objects it doesn't already own);
then a real `helm upgrade`, a deliberately broken `--atomic` upgrade that
auto-rolls back, and a manual `helm rollback` — all with zero Pod
disruption and the hit counter running throughout. GitLab and Harbor are a
separate, later pass. Manual: [CAPSTONE/Stage11-Helm/LAB-MANUAL.md](../CAPSTONE/Stage11-Helm/LAB-MANUAL.md).

## Prerequisites

```bash
helm version --short   # this cluster already had v3.21.3 installed
git --version
```
