# Output — ex06 Best Practices

Real run against `lab-g2-vm2`, 2026-09-16.

## The most important, honest finding: `helm lint` catches far less than you'd think

[anti-pattern-chart/](anti-pattern-chart/) deliberately packs in real
anti-patterns: a hardcoded resource name, a hardcoded namespace, no
`app.kubernetes.io/*` labels, a floating `:latest` tag, and zero resource
limits.

```
$ helm lint anti-pattern-chart
[INFO] Chart.yaml: icon is recommended
[INFO] values.yaml: file does not exist
1 chart(s) linted, 0 chart(s) failed

$ helm lint ../ex02-charts-and-values/mychart     # a normal, properly scaffolded chart
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed
```

**`helm lint` said nothing at all about the hardcoded name, the hardcoded
namespace, the missing labels, the floating tag, or the missing resource
limits.** It only checks chart *structure* (valid YAML, required
`Chart.yaml` fields, template syntax) — not semantic best practices. Those
need a human reviewer, or a dedicated policy/scanning tool (OPA/Kyverno
admission policies, or an image/config scanner like Day-11's Trivy).

## Proving the real, concrete consequences empirically

```
$ helm install release-a anti-pattern-chart -n day13-helm-gitops
STATUS: deployed

$ kubectl get deployment my-hardcoded-app-name -n default
my-hardcoded-app-name   1/1   1   1   16s        # landed in "default", NOT day13-helm-gitops!

$ kubectl get deployment my-hardcoded-app-name -n default -o jsonpath='{.spec.template.spec.containers[0].resources}'
{}                                                 # zero limits, genuinely unbounded

$ helm install release-b anti-pattern-chart -n day13-helm-gitops
Error: INSTALLATION FAILED: Unable to continue with install: Deployment
"my-hardcoded-app-name" in namespace "default" exists and cannot be
imported into the current release: invalid ownership metadata; annotation
validation error: key "meta.helm.sh/release-name" must equal "release-b":
current value is "release-a"
```

Three real, distinct consequences from things `helm lint` said nothing
about: the `-n day13-helm-gitops` flag was **silently ignored** (the
hardcoded `namespace: default` in the template wins), resources really are
unbounded, and a second install of the exact same chart **fails outright**
— not a style complaint, a hard collision. (`helm uninstall release-a`
still worked correctly even though its resources live in a different
namespace than the release secret — Helm's manifest tracking follows the
resources, not just the release's own namespace.)

## `--atomic`: automatic rollback on a real failed upgrade

**Without `--atomic`** — a real broken-image upgrade:

```
$ helm upgrade chart-demo ../ex02-charts-and-values/mychart -n day13-helm-gitops \
    --set image.repository=this-image-does-not-exist-... --set image.tag=bad --wait --timeout=25s
Error: UPGRADE FAILED: context deadline exceeded

$ helm status chart-demo -n day13-helm-gitops | grep STATUS
STATUS: failed

$ kubectl get pods -l app.kubernetes.io/instance=chart-demo
chart-demo-mychart-6c55459966-zj45c   0/1   ErrImagePull    <- BROKEN POD LEFT RUNNING
chart-demo-mychart-7859b9b6bd-k7fgs   1/1   Running
```

The release is left in `failed` state, **and the broken Pod is left in the
cluster** right alongside the last-good one — nothing fixes this
automatically; a human has to notice and run `helm rollback` manually
(which is exactly what was done to recover here).

**With `--atomic`** — the identical broken upgrade:

```
$ helm upgrade chart-demo ../ex02-charts-and-values/mychart -n day13-helm-gitops \
    --set image.repository=this-image-does-not-exist-... --set image.tag=bad --atomic --timeout=25s
Error: UPGRADE FAILED: release chart-demo failed, and has been rolled back
due to atomic being set: context deadline exceeded

$ helm status chart-demo -n day13-helm-gitops | grep STATUS
STATUS: deployed          <- NOT "failed"

$ kubectl get pods -l app.kubernetes.io/instance=chart-demo
(all Running - no broken Pod left behind)

$ helm history chart-demo -n day13-helm-gitops | tail -2
8   failed     Upgrade "chart-demo" failed: context deadline exceeded
9   deployed   Rollback to 7                                            <- AUTOMATIC
```

Same failure, same timeout — but `--atomic` triggered the rollback
**itself**, the moment the timeout fired, leaving the cluster in a known-
good state with no manual intervention and no broken Pods ever left
running for long. **This is the single most important flag for any
scripted/CI/GitOps `helm upgrade` call** (ex07 uses it for exactly this
reason).

## Inspect before you install

```
$ helm show chart bitnami/redis | head -3
$ helm show values bitnami/redis | head -10
## @param global.imageRegistry Global Docker image registry
## @param global.redis.password Global Redis(R) password ...
```

`helm show chart`/`helm show values` read a chart's metadata and full
default configuration **without installing anything** — the correct way to
know what a third-party chart will actually do to your cluster before
running `helm install` on it blind.

## Semantic versioning: the chart version, not the app version

```
$ helm package anti-pattern-chart -d /tmp/helm-lab-packages
Successfully packaged chart and saved it to: .../anti-pattern-chart-0.1.0.tgz

$ sed -i 's/version: 0.1.0/version: 0.2.0/' anti-pattern-chart/Chart.yaml
$ helm package anti-pattern-chart -d /tmp/helm-lab-packages
Successfully packaged chart and saved it to: .../anti-pattern-chart-0.2.0.tgz
```

`Chart.yaml`'s `version:` (the chart's own SemVer) is a **separate number**
from `appVersion:` (the version of the software the chart deploys) — a
chart's packaging/templates can get a patch bump without the underlying
app changing at all, and vice versa. A repository's `index.yaml` (ex01)
keys entries by this chart version, not the app version.

## Cleanup

```
$ helm uninstall release-a -n day13-helm-gitops   # already done above
$ rm -rf /tmp/helm-lab-packages
```
