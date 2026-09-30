# Output — ex05 Releases, Upgrade & Rollback

Real run against `lab-g2-vm2`, 2026-09-16. Reuses `chart-demo`'s real
4-revision history from ex02 rather than manufacturing artificial ones.

## Releases: every install/upgrade this day has made is tracked

```
$ helm list -n day13-helm-gitops
NAME            REVISION   STATUS     CHART            APP VERSION
arch-demo       1          deployed   nginx-25.1.12    1.31.6
chart-demo      4          deployed   mychart-0.1.0    1.16.0
umbrella-demo   3          deployed   umbrella-0.1.0   1.0

$ helm history chart-demo -n day13-helm-gitops
REVISION  STATUS      DESCRIPTION
1         superseded  Install complete
2         superseded  Upgrade complete
3         superseded  Upgrade complete
4         deployed    Upgrade complete
```

Every `install`/`upgrade` this course already ran on `chart-demo` (ex02's
values-precedence demo: 1 → 3 → 5 → 1 replicas) is a real, permanent
revision in this history — nothing about "history" here is staged for this
lab.

## Rollback: a real, important, often-misunderstood behavior

```
$ kubectl get pods -l app.kubernetes.io/instance=chart-demo --no-headers | wc -l
1                                    # current: revision 4, replicaCount=1

$ helm rollback chart-demo 2 -n day13-helm-gitops
Rollback was a success!

$ kubectl get pods -l app.kubernetes.io/instance=chart-demo --no-headers | wc -l
3                                    # revision 2's replicaCount=3, applied for real
```

```
$ helm history chart-demo -n day13-helm-gitops
REVISION  STATUS      DESCRIPTION
1         superseded  Install complete
2         superseded  Upgrade complete
3         superseded  Upgrade complete
4         superseded  Upgrade complete
5         deployed    Rollback to 2
```

**Rollback does NOT rewind the pointer to revision 2** — it creates a
**brand-new revision 5** whose content matches revision 2. `helm history`
never shrinks; every rollback is itself a fully auditable event with its
own timestamp. This matters operationally: "rolled back twice" leaves a
real, inspectable trail (`Rollback to 2`, `Rollback to 4`, etc.), not a
silently rewritten history.

## A second, independent rollback — and a real error case

```
$ helm upgrade arch-demo bitnami/nginx -n day13-helm-gitops --set replicaCount=2 ...
REVISION: 2
$ kubectl get pods -l app.kubernetes.io/instance=arch-demo --no-headers | wc -l
2

$ helm rollback arch-demo 1 -n day13-helm-gitops
Rollback was a success!
$ kubectl get pods -l app.kubernetes.io/instance=arch-demo --no-headers | wc -l
1

$ helm rollback arch-demo 99 -n day13-helm-gitops
Error: release has no 99 version
```

A rollback target that doesn't exist fails cleanly and immediately — no
partial rollback, no ambiguity.

## `helm upgrade --install`: the idempotent pattern GitOps pipelines rely on

```
$ helm upgrade --install arch-demo bitnami/nginx -n day13-helm-gitops --set replicaCount=1 ...
STATUS: deployed
REVISION: 4
```

`upgrade --install` does the right thing whether the release already
exists (upgrades it) or not (installs it fresh) — the exact command a CI/CD
or GitOps reconciler (ex07) can run unconditionally on every commit,
without first checking "does this release exist yet."

## Cleanup

All three releases (`arch-demo`, `chart-demo`, `umbrella-demo`) are left
running — final teardown happens once at the end of the whole day.
