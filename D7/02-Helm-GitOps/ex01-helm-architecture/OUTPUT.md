# Output — ex01 Helm Architecture & Repositories

Real run against `lab-g2-vm2`, 2026-09-16. Helm `v3.21.3` was already
installed on this host.

## Architecture: no Tiller, client-only

```
$ helm version --short
v3.21.3+g1ad6e68
```

Helm v2 required a server-side component (Tiller) running inside the
cluster with broad RBAC — a real, historical security problem. Helm v3
removed it entirely: `helm` is just a client binary that talks straight to
the Kubernetes API using **your own** kubeconfig credentials and RBAC.
Nothing extra is running in this cluster because of Helm itself.

## Repositories: a real, live chart repo

```
$ helm repo add bitnami https://charts.bitnami.com/bitnami
"bitnami" has been added to your repositories
$ helm repo update
Successfully got an update from the "bitnami" chart repository

$ helm search repo bitnami/nginx
NAME             CHART VERSION   APP VERSION   DESCRIPTION
bitnami/nginx    25.1.12         1.31.6        NGINX Open Source ...
```

A repo is nothing more than an `index.yaml` file listing chart versions and
their download URLs — `helm repo add` just registers that URL locally,
`helm repo update` re-fetches the index.

## Installing a real chart from that repo

```
$ helm install arch-demo bitnami/nginx -n day13-helm-gitops \
    --set service.type=ClusterIP --set replicaCount=1 \
    --set resources.requests.cpu=20m --set resources.requests.memory=32Mi \
    --set resources.limits.cpu=100m --set resources.limits.memory=64Mi

NAME: arch-demo
LAST DEPLOYED: Wed Sep 16 08:53:21 2026
NAMESPACE: day13-helm-gitops
STATUS: deployed
REVISION: 1

⚠ WARNING: Since August 28th, 2025, only a limited subset of images/charts
are available for free. Subscribe to Bitnami Secure Images ...
```

A real, current finding worth flagging: **Bitnami's charts changed
licensing/availability in August 2025** — many Bitnami charts now pull from
a restricted image set unless subscribed. This particular chart/image still
pulled and ran fine here, but don't assume every Bitnami chart will.

```
$ kubectl get pods -n day13-helm-gitops
arch-demo-nginx-565ccdbd7d-92222   1/1   Running
```

## The real architecture fact: a release IS a Kubernetes Secret

```
$ kubectl get secrets -n day13-helm-gitops -l owner=helm
NAME                              TYPE                 DATA   AGE
sh.helm.release.v1.arch-demo.v1   helm.sh/release.v1   1      19s
```

Helm v3's default storage backend for release state is a `Secret` object,
right in the same namespace as the release — not an external database, not
a ConfigMap (the v2 default). Decoded for real:

```
$ kubectl get secret sh.helm.release.v1.arch-demo.v1 -n day13-helm-gitops \
    -o jsonpath='{.data.release}' | base64 -d | base64 -d | gunzip | python3 -m json.tool
{
  "name": "arch-demo",
  "version": 1,
  "chart": {"metadata": {"name": "nginx", "version": "25.1.12"}},
  "manifest": "... the full rendered YAML Helm applied ..."
}
```

Double base64 (the Secret's own encoding, plus Helm's internal encoding)
plus gzip compression, unwrapping to a JSON document containing the chart
metadata, the values used, and the **entire rendered manifest** that was
actually applied — this is exactly what `helm history`/`helm rollback`
(ex05) read to know what to revert to.

## Cleanup

Left running — ex05 (Releases, Upgrade & Rollback) exercises this exact
release's revision history next.
