# Output — ex03 Templates Deep Dive

Real run against `lab-g2-vm2`, 2026-09-16. A small, purpose-built chart
([template-lab/](template-lab/)) so every templating feature demonstrated
is isolated and easy to trace back to a specific line.

## `helm template`: purely offline rendering, proven

```
$ helm lint template-lab
1 chart(s) linted, 0 chart(s) failed

$ helm template lab1 template-lab
---
# Source: template-lab/templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: lab1-template-lab-config
  labels:
    app.kubernetes.io/managed-by: Helm
    chart-version: 0.1.0
data:
  environment: staging
  log-level: "debug"
  database-host: "db.internal.local"
  feature-flags: |
    - beta-search
    - dark-mode
```

Every feature demonstrated in one ConfigMap:
- **`include`** (`_helpers.tpl`'s `template-lab.fullname`) → `lab1-template-lab-config`, consistent naming without repeating the concatenation logic everywhere.
- **Built-in objects**: `.Release.Service` → `Helm`, `.Chart.Version` → `0.1.0`, `.Values.environment` → `staging`.
- **`if`/`else`**: `environment != "production"` → `log-level: "debug"`.
- **`default` pipeline**: `databaseHost` was left unset in `values.yaml` — `| default "db.internal.local"` filled it in.
- **`range`**: looped `featureFlags` (a real list) into YAML list items.

## Real proof `helm template` needs ZERO cluster access

```
$ KUBECONFIG=/nonexistent-kubeconfig helm template lab1 template-lab
--- (renders exactly the same, no error)
```

```
$ KUBECONFIG=/nonexistent-kubeconfig helm install lab1 template-lab -n day13-helm-gitops --dry-run=server
Error: INSTALLATION FAILED: Kubernetes cluster unreachable: Get "http://localhost:8080/version": ... connection refused
```

**A real, concrete distinction, not a documentation claim**: `helm
template` is pure local rendering (no API calls at all — it worked with a
kubeconfig pointing at nothing); `helm install --dry-run=server` (or
plain `--dry-run` in newer Helm, which also validates client-side) still
needs to reach the real API server for `Capabilities`/API-version checks
and (with `--dry-run=server`) full server-side validation. Use `helm
template` in CI pipelines that shouldn't need cluster credentials at all;
use `--dry-run=server` right before a real install when you want the API
server's own opinion.

## `if`/`else` branching on real input

```
$ helm template lab1 template-lab --set environment=production | grep log-level
  log-level: "warn"
```

Same template, different output — confirmed the `eq` comparison actually
branches, not just documented behavior.

## `required`: a real, hard, fail-fast render error

```
$ helm template lab1 template-lab --set apiKeyEnabled=true
Error: execution error at (template-lab/templates/secret.yaml:11:14): apiKey must be set when apiKeyEnabled is true

$ helm template lab1 template-lab --set apiKeyEnabled=true --set apiKey=real-value-123
kind: Secret
metadata:
  name: lab1-template-lab-secret
```

`required` stops the **entire render** at the exact line/file — not a
warning, not a partially-rendered manifest with an empty value silently
applied. This is the mechanism that turns "the app crashed at 2am because
a Secret was empty" into "the `helm install` itself refused to run."

## Cleanup

Nothing was ever installed in this lab — every command was `helm template`
or `helm lint`, both entirely local. No cluster objects to remove.
