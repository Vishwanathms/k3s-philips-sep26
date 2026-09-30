# Output — ex04 Dependencies

Real run against `lab-g2-vm2`, 2026-09-16. The [umbrella/](umbrella/) chart
declares two dependencies in its `Chart.yaml`: a **local** subchart
(`web/`, vendored right in `charts/`) and a **real remote** subchart
(bitnami's `common` library chart, pulled from a live repo) — deliberately
a library chart (deploys zero resources) to keep this lab's footprint on
the shared cluster minimal while still exercising a genuine remote pull.

```yaml
dependencies:
  - name: web
    version: "0.1.0"
    repository: "file://charts/web"
  - name: common
    version: "2.x.x"
    repository: "https://charts.bitnami.com/bitnami"
```

## `helm dependency update` — a real, current finding

```
$ helm dependency update
Saving 2 charts
Downloading common from repo https://charts.bitnami.com/bitnami
Pulled: registry-1.docker.io/bitnamicharts/common:2.41.0
Digest: sha256:669301594ad66a7401a47d26c6f0b763b95e44af667c57228e552920eb8feb66

$ ls charts/
common-2.41.0.tgz   web/   web-0.1.0.tgz
```

The `repository:` field said the classic HTTP chart repo
(`https://charts.bitnami.com/bitnami`), but the actual chart was pulled
from `registry-1.docker.io/bitnamicharts/common` — an **OCI registry**.
Bitnami's HTTP `index.yaml` now points chart downloads at OCI references
rather than plain `.tgz` URLs (part of their broader 2025 distribution
changes, the same shift ex01 noted about their free-tier image
restrictions). Dependencies are always fetched and stored as `.tgz`
archives in `charts/`, whether local (`file://`) or remote — Helm doesn't
extract them, it repackages/re-reads the archive at render time.

## Real install: one Pod from the local subchart, zero from the library chart

```
$ helm lint .
1 chart(s) linted, 0 chart(s) failed

$ helm install umbrella-demo . -n day13-helm-gitops
STATUS: deployed

$ kubectl get pods -n day13-helm-gitops -l app=umbrella-demo-web
umbrella-demo-web-79565f9cc9-wxtjq   1/1   Running

$ kubectl get all -n day13-helm-gitops -l app.kubernetes.io/instance=umbrella-demo
(no resources match this label from the common chart at all)
```

`common` is `type: library` — it contributes template **helpers** other
charts can `include`, and deploys nothing itself. Real, verified: the only
Pod that exists came from the `web` subchart.

## Values namespacing — proved with real replica counts

```
$ helm upgrade umbrella-demo . -n day13-helm-gitops --set web.replicaCount=3
$ kubectl get pods -n day13-helm-gitops -l app=umbrella-demo-web --no-headers | wc -l
3
```

The umbrella chart's own `values.yaml` has a top-level `web:` key —
everything under it is passed to the `web` subchart as **its own root
values** (so inside `web/templates/`, it's just `.Values.replicaCount`, not
`.Values.web.replicaCount`). Overriding `web.replicaCount` at install/
upgrade time from the umbrella level reached the subchart and changed the
real replica count, confirming the namespacing works exactly as the chart
was written to expect.

```
$ helm upgrade umbrella-demo . -n day13-helm-gitops --set web.replicaCount=1   # scaled back down
```

## Cleanup

Left running at 1 replica. Full teardown happens at the end of the day
alongside every other lab's releases.
