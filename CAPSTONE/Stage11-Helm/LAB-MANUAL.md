# Capstone stage 11 — One chart, real upgrades, real rollbacks (Day 13)

## Scenario

Since Stage 02 the capstone has been deployed with `kubectl apply -f
manifests/` — a full snapshot every time, no history, no single command to
go back a version. Today it becomes **one Helm chart**: a real release with
a revision history, a scriptable upgrade path, and a rollback that actually
works — the same three things Day 13's Lab 5 taught on a throwaway chart,
now done on the app you've been running all course.

This stage is scoped to exactly that: **package it, upgrade it, roll it
back.** Pushing the chart to a git repo and rebuilding the images through
Harbor are separate, later exercises — not needed to get real value from
Helm today.

## What changed since Stage 10

| File | Change |
|---|---|
| `chart/capstone/` | **new**: the entire Stage 10 manifest set, converted into one Helm chart |
| `chart/capstone/values.yaml` | the handful of things an upgrade actually changes: image tags, web's replica count, the api HPA's range |
| `scripts/adopt-into-helm.sh` | **new, one-time**: labels/annotates every existing live object so Helm adopts it instead of refusing to install |

`manifests/` from Stage 10 isn't touched or removed — it's what the chart
was generated from, kept for comparison.

## Learning objectives

- explain why Helm refuses to install over objects it doesn't already own,
  and how to adopt existing, unmanaged objects into a release without
  recreating them
- read `helm history` as an audit log, not just a list
- use `helm upgrade` to change one value and watch only the affected
  objects roll
- explain what `--atomic` buys you: a failed upgrade that fails *closed*
- tell a manual `helm rollback` from an atomic auto-rollback, and predict
  what `helm rollback <bad revision>` does before running it

## Before starting

Stage 10 running, healthy (or catch up with its manual):

```bash
cd ~/Documents/k3s-training/CAPSTONE/Stage11-Helm
export NODE_IP=$(hostname -I | awk '{print $1}')
kubectl -n capstone get pods              # 6 Pods, all 2/2 Running
curl -s -H 'Host: capstone.k3s.local' http://$NODE_IP/api/hits; echo
helm lint chart/capstone                  # 0 charts failed
```

---

## H1 — Why `helm install` refuses a running app (5 min)

Try it, on purpose, before adopting anything:

```bash
helm install capstone chart/capstone -n capstone --dry-run
```

Expected:

```
Error: INSTALLATION FAILED: Unable to continue with install: PriorityClass
"capstone-data" in namespace "" exists and cannot be imported into the
current release: invalid ownership metadata; label validation error:
missing key "app.kubernetes.io/managed-by": must be set to "Helm";
annotation validation error: missing key "meta.helm.sh/release-name":
must be set to "capstone"; annotation validation error: missing key
"meta.helm.sh/release-namespace": must be set to "capstone"
```

Helm 3 tracks ownership with one label and two annotations on every object
it manages. Every object here was created by plain `kubectl apply`, so none
of them carry that metadata — Helm has no way to tell "this is safe to
adopt" from "this would overwrite someone else's PriorityClass", so it
refuses. The error names exactly what's missing.

> **Checkpoint H1:** you can say which 3 keys Helm checks, and why it
> refuses rather than guessing.

## H2 — Adopt, without recreating anything (10 min)

```bash
kubectl -n capstone get pods -o custom-columns='NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp'
./scripts/adopt-into-helm.sh
```

The script adds the same label + 2 annotations to every object the chart
manages — nothing is deleted, scaled, or restarted, only metadata changes.

```bash
helm install capstone chart/capstone -n capstone
```

Expected: `STATUS: deployed`, `REVISION: 1` — not an error this time.
Compare Pod identity before and after:

```bash
kubectl -n capstone get pods -o custom-columns='NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp'
curl -s -H 'Host: capstone.k3s.local' http://$NODE_IP/api/hits; echo
```

Expected: **identical** Pod names, creation timestamps and restart counts
to before H2 — this is the whole point. Adoption changes who's allowed to
manage an object, never the object's running Pods. The counter kept
climbing the entire time.

> **Checkpoint H2:** you can point to the exact evidence that nothing
> restarted (not just "it looks fine").

## H3 — A real upgrade (10 min)

```bash
helm upgrade capstone chart/capstone -n capstone --set web.replicaCount=3
kubectl -n capstone rollout status deploy/web --timeout=60s
kubectl -n capstone get pods -l app=web
helm history capstone -n capstone
```

Expected: 3 web Pods, the **original two untouched** (same names, `AGE`
unchanged) plus one new one; `helm history` shows revision 2, `Upgrade
complete`. Only the Deployment that actually referenced
`web.replicaCount` changed — redis, api, the NetworkPolicies, everything
else in the chart is byte-for-byte the same manifest Helm already owns, so
`helm upgrade` leaves it alone.

> **Checkpoint H3:** you can say why only web's Pods changed, not all 6.

## H4 — `--atomic`: a failed upgrade that fails closed (10 min)

Ship a "release" with two changes at once — one good, one broken — the way
a real deploy often does:

```bash
helm upgrade capstone chart/capstone -n capstone \
  --set web.replicaCount=3 --set api.image.tag=9.9.9-missing --atomic --timeout=45s
```

Expected, after the timeout:

```
Error: UPGRADE FAILED: release capstone failed, and has been rolled back due to atomic being set: context deadline exceeded
```

Check what actually happened:

```bash
helm history capstone -n capstone
kubectl -n capstone get pods -l app=api
kubectl -n capstone get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curl -s -H 'Host: capstone.k3s.local' http://$NODE_IP/api/hits; echo
```

Expected: `helm history` shows revision 3 `failed`, then revision 4
`Rollback to 2` — Helm rolled the **entire release** back to its last good
state automatically, not just the broken piece. The api Pods were never
touched (still the original 2, still `capstone-api:1.0.0`), and the
counter never stopped. Without `--atomic`, the bad api tag would have been
left half-applied — some api Pods on the old image, some
`ImagePullBackOff` — exactly Day 12's Stage 10 fault 2, except this time
self-inflicted by a bad deploy instead of an instructor's script.

> **Checkpoint H4:** you can say what `--atomic` actually rolled back to,
> and why it's revision 2, not revision 1.

## H5 — Manual rollback, and a rollback that can't succeed (10 min)

```bash
helm rollback capstone 1 -n capstone
kubectl -n capstone rollout status deploy/web --timeout=60s
kubectl -n capstone get pods -l app=web
helm history capstone -n capstone
```

Expected: back to 2 web Pods (the original two, `web.replicaCount` from
revision 1), a **new** revision 5 recorded as `Rollback to 1` — history
only ever grows, a rollback is itself an audited event, not a rewrite.

```bash
helm rollback capstone 99 -n capstone
```

Expected: `Error: release has no 99 version` — fails immediately and
cleanly, no partial rollback, no ambiguity.

> **Checkpoint H5:** looking at `helm history`'s full list, you can say
> what state the release is in right now and how you know.

---

## Troubleshooting

| Symptom | Likely cause / check |
|---|---|
| `helm install` still refuses after running the adoption script | check `kubectl get <kind> <name> -o yaml \| grep -A2 'meta.helm.sh'` — the annotation must match this exact release name and namespace |
| `helm upgrade` hangs, then times out without `--atomic` | the new Pods can't pass readiness (bad image, bad probe) and the rollout can't progress — same class of stuck rollout as Stage 10's T3; `--atomic` is what turns this into a clean revert |
| after `--atomic` failed, `helm history` doesn't show a `Rollback to N` line | the timeout fired before Helm's own rollback finished; wait a few seconds and re-check, or the release may be `pending-rollback` — `helm status capstone -n capstone` |
| `values.yaml` value doesn't seem to take effect | confirm the template actually reads it (`grep -rn '.Values.foo' chart/capstone/templates/`) — a value with no matching template read is silently ignored |
| `helm lint` warns "icon is recommended" | cosmetic only, safe to ignore for an internal chart |

## Before you leave — keep it running

The release stays installed; there's nothing to revert. To catch up later
on a cluster that's still on raw `kubectl apply` manifests:

```bash
cd ~/Documents/k3s-training/CAPSTONE/Stage11-Helm
./scripts/adopt-into-helm.sh
helm install capstone chart/capstone -n capstone
```

From here on, manage the app with `helm upgrade`/`helm rollback`, not
`kubectl apply -f manifests/` — mixing the two makes Helm's next `diff`
lie about what's actually different.
