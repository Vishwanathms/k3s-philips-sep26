# ex07 — RBAC for a real human user (x509 client cert) with read-only Pod access

`ex06` gave an in-cluster **ServiceAccount** limited permissions. This
exercise does the same thing for a **human user**: it creates a genuine
Kubernetes `User` identity (`alice`, authenticated by an x509 client
certificate — k3s has no built-in user database or OIDC, so this is the
standard way to hand a person their own identity) and grants that identity
**read-only access to Pods** in one namespace: it can list Pods and read
their logs, but cannot create, delete, exec into, or touch any other kind
of object (Deployments, Secrets, …).

Tested on k3s `v1.36.4+k3s1`; see [OUTPUT.md](OUTPUT.md) for the captured
run. Step-by-step instructions (including how the user identity itself is
built) are in [LAB-MANUAL.md](LAB-MANUAL.md).

## Objects

| Object | Name | Purpose |
|---|---|---|
| Namespace | `rbac-user-pod-demo` | isolates the exercise |
| Deployment | `demo-app` (2 replicas, nginx) | the Pods `alice` is allowed to view |
| Secret | `demo-secret` | dummy object used to prove the Role does *not* leak beyond Pods |
| Role | `pod-reader` | `get/list/watch` on `pods`, `get` on `pods/log` — nothing else |
| RoleBinding | `pod-reader-binding` | binds `pod-reader` to `User alice` |
| User | `alice` | x509 client cert, `CN=alice`, `O=developers`, issued via the cluster's `CertificateSigningRequest` API |

Kubernetes has no `User` API object — a "user" is just whatever identity
the client certificate (or token) asserts. RBAC then binds a Role to that
identity by name.

## Files

```
00-namespace.yaml      Namespace rbac-user-pod-demo
01-demo-pods.yaml      Deployment demo-app (the Pods to view)
02-demo-secret.yaml    Secret demo-secret (negative-permission check)
03-role.yaml           Role pod-reader (get/list/watch pods, get pods/log)
04-rolebinding.yaml    RoleBinding pod-reader-binding -> User alice
scripts/create-user-alice.sh   generates alice's key/cert/kubeconfig via CSR API
scripts/cleanup-user-alice.sh  removes the CSR object and generated files
```

`scripts/create-user-alice.sh` writes alice's private key, signed
certificate, and a standalone kubeconfig into `alice-identity/`. That
directory is **git-ignored** (see repo `.gitignore`) — a private key must
never be committed.

## Quick start

```bash
kubectl apply -f 00-namespace.yaml -f 01-demo-pods.yaml -f 02-demo-secret.yaml \
  -f 03-role.yaml -f 04-rolebinding.yaml
kubectl rollout status deployment/demo-app -n rbac-user-pod-demo --timeout=120s

./scripts/create-user-alice.sh

KCFG=alice-identity/alice.kubeconfig
NS=rbac-user-pod-demo

kubectl --kubeconfig="$KCFG" auth whoami                 # Username: alice
kubectl --kubeconfig="$KCFG" get pods -n "$NS"            # allowed
kubectl --kubeconfig="$KCFG" get secret demo-secret -n "$NS"  # Forbidden
```

See [LAB-MANUAL.md](LAB-MANUAL.md) for the full walkthrough and
[OUTPUT.md](OUTPUT.md) for the exact commands and output from a real run.

## Cleanup

```bash
./scripts/cleanup-user-alice.sh
kubectl delete namespace rbac-user-pod-demo
```
