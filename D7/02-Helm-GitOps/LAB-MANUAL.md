# Lab manual — Helm & GitOps

## Learning objectives

By the end of this lab, students can explain Helm v3's client-only
architecture and inspect a release's real on-cluster storage, author and
lint a chart, reason precisely about values-file precedence, use Helm's
templating engine's built-in objects/functions/control structures (and
know when `helm template` needs no cluster access at all), declare and pull
both local and remote chart dependencies, read and act on release history
(including what `rollback` actually does), spot real anti-patterns `helm
lint` won't catch, use `--atomic` for safe scripted upgrades, and build (and
explain) the actual reconciliation loop behind GitOps tooling.

## Before starting

```bash
kubectl apply -f 00-namespace.yaml
export NS=day13-helm-gitops
helm version --short
```

---

## Lab 1 — Helm Architecture & Repositories

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo bitnami/nginx

helm install arch-demo bitnami/nginx -n "$NS" --set service.type=ClusterIP --set replicaCount=1 \
  --set resources.requests.cpu=20m --set resources.requests.memory=32Mi \
  --set resources.limits.cpu=100m --set resources.limits.memory=64Mi

kubectl get secrets -n "$NS" -l owner=helm     # the release itself, as a real Secret
kubectl get secret sh.helm.release.v1.arch-demo.v1 -n "$NS" -o jsonpath='{.data.release}' \
  | base64 -d | base64 -d | gunzip | python3 -m json.tool | head -10
```

---

## Lab 2 — Charts and Values

```bash
cd ex02-charts-and-values
helm create mychart
helm lint mychart
helm install chart-demo mychart -n "$NS" \
  --set resources.requests.cpu=20m --set resources.requests.memory=32Mi \
  --set resources.limits.cpu=100m --set resources.limits.memory=64Mi

kubectl get pods -n "$NS" -l app.kubernetes.io/instance=chart-demo   # 1 replica (chart default)

helm upgrade chart-demo mychart -n "$NS" -f values-scaled.yaml ...   # replicaCount: 3
kubectl get pods -n "$NS" -l app.kubernetes.io/instance=chart-demo --no-headers | wc -l   # 3

helm upgrade chart-demo mychart -n "$NS" -f values-scaled.yaml --set replicaCount=5 ...
kubectl get pods -n "$NS" -l app.kubernetes.io/instance=chart-demo --no-headers | wc -l   # 5 - --set wins
```

---

## Lab 3 — Templates Deep Dive

```bash
cd ../ex03-templates-deep-dive
helm lint template-lab
helm template lab1 template-lab                          # offline rendering
helm template lab1 template-lab --set environment=production | grep log-level
helm template lab1 template-lab --set apiKeyEnabled=true  # real `required` failure
helm template lab1 template-lab --set apiKeyEnabled=true --set apiKey=x   # succeeds

# prove helm template needs no cluster access:
KUBECONFIG=/nonexistent-kubeconfig helm template lab1 template-lab
```

---

## Lab 4 — Dependencies

```bash
cd ../ex04-dependencies/umbrella
helm dependency update       # pulls charts/web (local) + charts/common (real remote)
helm lint .
helm install umbrella-demo . -n "$NS"
kubectl get pods -n "$NS" -l app=umbrella-demo-web        # from the LOCAL subchart
kubectl get all -n "$NS" -l app.kubernetes.io/instance=umbrella-demo | grep -v web   # nothing from the library chart

helm upgrade umbrella-demo . -n "$NS" --set web.replicaCount=3   # namespaced value reaches the subchart
```

---

## Lab 5 — Releases, Upgrade & Rollback

```bash
cd ../../ex05-releases-upgrade-rollback
helm list -n "$NS"
helm history chart-demo -n "$NS"

helm rollback chart-demo 2 -n "$NS"
helm history chart-demo -n "$NS"     # note: a NEW revision, "Rollback to 2"

helm rollback chart-demo 99 -n "$NS"   # real error: no such revision
helm upgrade --install arch-demo bitnami/nginx -n "$NS" ...   # the idempotent pattern
```

---

## Lab 6 — Best Practices

```bash
cd ../ex06-best-practices
helm lint anti-pattern-chart          # passes clean despite real anti-patterns
helm install release-a anti-pattern-chart -n "$NS"
kubectl get deployment my-hardcoded-app-name -n default    # landed in the WRONG namespace
helm install release-b anti-pattern-chart -n "$NS"          # real collision error
helm uninstall release-a -n "$NS"

# --atomic:
helm upgrade chart-demo ../ex02-charts-and-values/mychart -n "$NS" \
  --set image.repository=nonexistent --set image.tag=bad --atomic --timeout=25s
# compare to the same command WITHOUT --atomic - see OUTPUT.md for the full contrast

helm show values bitnami/redis | head -20    # inspect before installing
helm package anti-pattern-chart -d /tmp/pkgs # semantic versioning in the filename
```

---

## Lab 7 — GitOps Workflow

```bash
cd ../ex07-gitops-workflow
bash setup-git-remote.sh          # recreates the real local git remote
bash reconcile.sh                 # tick 1: first deploy from git

# make a real change:
$EDITOR /tmp/gitops-workdir/repo/gitops-app/values.yaml   # e.g. replicaCount: 3
cd /tmp/gitops-workdir/repo && git commit -am "v2" && git push
cd - && bash reconcile.sh         # tick 2: picks up the new commit

# drift correction - the actual point of GitOps:
kubectl scale deployment gitops-app -n "$NS" --replicas=10   # bypass git
bash reconcile.sh                 # tick 3: reverts the manual change back to git's truth
kubectl get pods -n "$NS" -l app=gitops-app --no-headers | wc -l   # back to 3

helm uninstall gitops-app -n "$NS"
rm -rf /tmp/gitops-remote.git /tmp/gitops-workdir
```

---

## Troubleshooting sequence

```bash
helm status <release> -n <ns>
helm history <release> -n <ns>
helm get values <release> -n <ns> --all
helm get manifest <release> -n <ns>       # exactly what was applied
helm lint <chart>                          # structural checks only - not a semantic-safety guarantee
```

| Symptom | Likely cause |
|---|---|
| `helm install` seems to have installed into the wrong namespace | check the chart's templates for a hardcoded `namespace:` field - `-n` doesn't override it |
| A second install of the same chart fails with an ownership/annotation error | a hardcoded resource name in the chart - two releases can't own the same object |
| Values I passed with `-f` don't seem to apply | check for a later `--set` on the same command line - `--set` always wins |
| `helm rollback` "succeeded" but `helm history` still shows all old revisions | expected - rollback creates a new revision, it never deletes history |
| A scripted `helm upgrade` leaves a broken release and a crashed Pod after a bad deploy | missing `--atomic` (and usually `--wait`/`--timeout`) |
| `helm template` renders fine but `helm install` fails | `helm template` never contacts the API server - it can't catch things that need real server-side validation |

## Cleanup

```bash
helm list -A | grep day13
kubectl delete namespace day13-helm-gitops
rm -rf /tmp/gitops-remote.git /tmp/gitops-workdir
```
