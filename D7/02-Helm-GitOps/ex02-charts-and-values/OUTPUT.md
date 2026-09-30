# Output — ex02 Charts and Values

Real run against `lab-g2-vm2`, 2026-09-16.

## Chart anatomy — a real chart, scaffolded, not hand-typed

```
$ helm create mychart
Creating mychart
$ find mychart -type f
mychart/Chart.yaml              # chart identity: name, version, appVersion
mychart/values.yaml              # the default configuration
mychart/templates/deployment.yaml
mychart/templates/service.yaml
mychart/templates/serviceaccount.yaml
mychart/templates/hpa.yaml
mychart/templates/ingress.yaml
mychart/templates/httproute.yaml   # Gateway API support, present by default now
mychart/templates/_helpers.tpl     # shared template snippets (naming conventions)
mychart/templates/NOTES.txt        # post-install message, itself a template
mychart/templates/tests/test-connection.yaml
```

Real, current `values.yaml` already documents a best practice inline:

```yaml
resources: {}
  # We usually recommend not to specify default resources and to leave this as a conscious
  # choice for the user. This also increases chances charts run on environments with little
  # resources, such as Minikube.
```

## Lint and dry-run before ever touching the cluster

```
$ helm lint mychart
==> Linting mychart
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed

$ helm install chart-demo mychart -n day13-helm-gitops --dry-run
NAME: chart-demo
STATUS: pending-install
--- (full rendered manifest follows, nothing applied)
```

## Real install, and a real, dynamic NOTES.txt

```
$ helm install chart-demo mychart -n day13-helm-gitops \
    --set resources.requests.cpu=20m --set resources.requests.memory=32Mi \
    --set resources.limits.cpu=100m --set resources.limits.memory=64Mi

NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace day13-helm-gitops -l "app.kubernetes.io/name=mychart,app.kubernetes.io/instance=chart-demo" ...)
  kubectl --namespace day13-helm-gitops port-forward $POD_NAME 8080:$CONTAINER_PORT
```

`NOTES.txt` is itself a Go template — the commands it prints are generated
per-install, referencing this exact release's real name and labels, not a
static string.

## Values precedence — proved with real pod counts, not documentation

| Source | `replicaCount` | Real Pods after applying |
|---|---|---|
| `values.yaml` (chart default) | `1` | 1 |
| `-f values-scaled.yaml` (`replicaCount: 3`) | `3` | **3** |
| `-f values-scaled.yaml` **+** `--set replicaCount=5` | `3` vs `5` | **5** |

```
$ helm upgrade chart-demo mychart -n day13-helm-gitops -f values-scaled.yaml ...
REVISION: 2
$ kubectl get pods -l app.kubernetes.io/instance=chart-demo --no-headers | wc -l
3

$ helm upgrade chart-demo mychart -n day13-helm-gitops -f values-scaled.yaml --set replicaCount=5 ...
REVISION: 3
$ kubectl get pods -l app.kubernetes.io/instance=chart-demo --no-headers | wc -l
5
```

`--set` won over `-f values-scaled.yaml` even though both were passed on
the same command — real, observed precedence order (lowest to highest):
chart's own `values.yaml` → `-f`/`--values` files (later files override
earlier ones) → `--set`/`--set-string`/`--set-file` (always wins).

```
$ helm get values chart-demo -n day13-helm-gitops
USER-SUPPLIED VALUES:
replicaCount: 5
resources: {limits: {...}, requests: {...}}
```

`helm get values` (without `--all`) shows exactly what was supplied across
every `-f`/`--set` ever passed for this release, merged — not the full
chart defaults (`--all` shows those too).

## Cleanup

Down-scaled and left running for now (see [ex06](../ex06-best-practices/OUTPUT.md)
which lints this exact `mychart` chart directory); fully removed at the end
of this day's overall cleanup.

```
$ helm upgrade chart-demo mychart -n day13-helm-gitops --set replicaCount=1 \
    --set resources.requests.cpu=20m --set resources.requests.memory=32Mi \
    --set resources.limits.cpu=100m --set resources.limits.memory=64Mi
```
