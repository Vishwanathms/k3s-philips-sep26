# D2 — Workloads, configuration & RBAC

Takes D1's python + redis app and makes its configuration explicit, then
locks down who may do what. Everything here runs in one namespace,
**`d2-workloads-rbac`**.

## Hands-on labs

| # | Lab | Proves | Verified run |
|---|-----|--------|--------------|
| 3 | [ex03-env-redis-host](ex03-env-redis-host/) | renaming the Redis `Service` breaks the app's built-in default, and an **env var** fixes it | [OUTPUT.md](ex03-env-redis-host/OUTPUT.md) |
| 4 | [ex04-configmap](ex04-configmap/) | the same value moved into a `ConfigMap` — config changes without touching the Deployment | [OUTPUT.md](ex04-configmap/OUTPUT.md) |
| 5 | [ex05-dockerhub-secret](ex05-dockerhub-secret/) | a `dockerconfigjson` Secret + `imagePullSecrets` authenticates the kubelet to a registry | [OUTPUT.md](ex05-dockerhub-secret/OUTPUT.md) |
| 6 | [ex06-rbac-serviceaccount](ex06-rbac-serviceaccount/) | a `ServiceAccount` scoped to **one named Deployment** — and what it is refused | [OUTPUT.md](ex06-rbac-serviceaccount/OUTPUT.md) |
| 7 | [ex07-rbac-user-pod-access](ex07-rbac-user-pod-access/) | a real human user via x509 client cert, with read-only Pod access | [OUTPUT.md](ex07-rbac-user-pod-access/OUTPUT.md) |

Numbering continues from D1, which ends at ex02.

Deeper RBAC material:
[ex06/REAL_WORLD_RBAC_AND_TROUBLESHOOTING.md](ex06-rbac-serviceaccount/REAL_WORLD_RBAC_AND_TROUBLESHOOTING.md).

## Namespace

Every manifest in D2 is pinned to `d2-workloads-rbac`. Create it once and make
it your default, so the commands in each exercise need no `-n`:

```bash
kubectl apply -f 00-namespace.yaml
kubectl config set-context --current --namespace=d2-workloads-rbac
```

ex06 and ex07 also mention namespaces like `payments-prod`, `catalog-staging`
and `imaging-dev` **inside their Role and RoleBinding examples**. Those are
illustrative scenario names for reading RBAC rules — the labs do not create
them.

Cleanup, and putting your context back:

```bash
kubectl delete namespace d2-workloads-rbac
kubectl config set-context --current --namespace=default
bash ex07-rbac-user-pod-access/scripts/cleanup-user-alice.sh   # removes alice's cert/kubeconfig
```

## Prerequisites

```bash
kubectl get nodes                     # Ready
kubectl auth can-i '*' '*'            # yes - you are admin; the labs then restrict others
```

ex05 needs a Docker Hub account — see
[CAPSTONE/LAB-MANUAL-Docker-Hub.md](../CAPSTONE/LAB-MANUAL-Docker-Hub.md) for
creating the ID and an access token.

## Assignment

[Assignment/](Assignment/) — covers D1 and D2 material only. Three broken
manifests in `Assignment/broken/` to diagnose and fix.

The assignment is set in its own fictional company and uses the namespaces
`imaging-dev` and `imaging-prod`, which **you create as part of the task** —
it deliberately does not reuse `d2-workloads-rbac`.

## Reference material

| File | What |
|---|---|
| [PPT1-Kubernetes_Workloads.pdf](PPT1-Kubernetes_Workloads.pdf) | Slide deck: Deployments, ReplicaSets, Pods |
| `LM01`–`LM04` `.docx` | Student handouts on RBAC: ServiceAccounts, user-based access, real-world design |
| [RBAC-Service-account.png](RBAC-Service-account.png) | Diagram: ServiceAccount → Role → RoleBinding |

## What comes next

D3 takes the same app and makes the **network** explicit: Service types, DNS,
NetworkPolicy and Ingress.
