# ex06 — RBAC with a limited ServiceAccount (k3s)

Create an in-cluster identity that can operate **one named Deployment** and
view Pods, but cannot create or delete Deployments. The lab is isolated in one
namespace and has been tested on k3s `v1.36.4+k3s1`; see [OUTPUT.md](OUTPUT.md).

## Objects

| Object | Name | Purpose |
|---|---|---|
| Namespace | `rbac-nginx-demo` | isolates the exercise |
| Deployment | `nginx-deploy` | the only workload the operator may change |
| ServiceAccount | `nginx-operator` | limited in-cluster identity |
| Role / RoleBinding | `nginx-deployment-manager` | grants that identity its permissions |

`resourceNames: [nginx-deploy]` makes the Deployment rule object-specific.
Consequently, `kubectl get deployments` is denied; use
`kubectl get deployment nginx-deploy`. Pod listing is intentionally allowed so
students can observe a rollout.

## Prerequisites

Use a k3s administrator kubeconfig. The `--as` checks require the current
identity to be allowed to impersonate ServiceAccounts.

```bash
kubectl get nodes                 # expect Ready
kubectl config current-context
```

## Apply

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-nginx-deploy.yaml
kubectl apply -f 02-serviceaccount.yaml
kubectl apply -f 03-role.yaml
kubectl apply -f 04-rolebinding.yaml
kubectl rollout status deployment/nginx-deploy -n rbac-nginx-demo --timeout=120s
kubectl get deploy,pods,sa,role,rolebinding -n rbac-nginx-demo
```

## Verify RBAC by impersonating the ServiceAccount

```bash
NS=rbac-nginx-demo
SA=system:serviceaccount:$NS:nginx-operator

# Allowed
kubectl auth can-i get deployment/nginx-deploy -n "$NS" --as="$SA"              # yes
kubectl auth can-i update deployment/nginx-deploy -n "$NS" --as="$SA"           # yes
kubectl auth can-i update deployment/nginx-deploy --subresource=scale -n "$NS" --as="$SA" # yes
kubectl auth can-i list pods -n "$NS" --as="$SA"                                 # yes

# Denied
kubectl auth can-i create deployments -n "$NS" --as="$SA"                       # no
kubectl auth can-i delete deployment/nginx-deploy -n "$NS" --as="$SA"           # no
kubectl auth can-i list deployments -n "$NS" --as="$SA"                         # no
```

The scale subresource needs an explicit Role rule: `kubectl scale` writes to
`deployments/scale`, not to `deployments`.

```bash
kubectl scale deployment/nginx-deploy --replicas=2 -n "$NS" --as="$SA"
kubectl rollout status deployment/nginx-deploy -n "$NS" --timeout=120s
kubectl get pods -n "$NS"
kubectl delete deployment/nginx-deploy -n "$NS" --as="$SA"  # Forbidden (expected)
```

## In-cluster test (optional)

Current k3s/Kubernetes (1.24+) does not auto-create a long-lived token Secret
for a ServiceAccount. The recommended approach is a projected, rotating token
mounted in a Pod.

```bash
kubectl apply -f 05-operator-pod.yaml
kubectl wait --for=condition=Ready pod/operator-box -n "$NS" --timeout=120s
kubectl exec -n "$NS" operator-box -- kubectl auth can-i update deployment/nginx-deploy --subresource=scale # yes
kubectl exec -n "$NS" operator-box -- kubectl auth can-i delete deployment/nginx-deploy                       # no
kubectl exec -n "$NS" operator-box -- kubectl get deployment nginx-deploy
kubectl exec -n "$NS" operator-box -- kubectl scale deployment/nginx-deploy --replicas=1
```

`operator-box` runs `kubectl proxy`: the small `rancher/kubectl` image has no
`sh` or `sleep`, so a shell-based keepalive fails. For a short-lived token for
an external API client, use `kubectl create token nginx-operator -n "$NS"`.
Never commit a token to the repository.

## Troubleshooting

| Symptom | Check / fix |
|---|---|
| Cannot connect or `Unauthorized` | Confirm `kubectl get nodes` works and select the correct context. |
| Scale returns `Forbidden` | Reapply `03-role.yaml`; it must include `deployments/scale`. |
| `get deployments` returns `Forbidden` | Expected for an object-limited Role. Request the named object instead. |
| `--as` returns `Forbidden` | Your admin lacks impersonation permission. Test from `operator-box`, or use an admin kubeconfig. |
| `operator-box` is not Ready | `kubectl describe pod operator-box -n "$NS"`; reapply the provided manifest, which uses `kubectl proxy`. |
| No ServiceAccount token Secret | Expected on k3s/Kubernetes 1.24+. Use the Pod token or `kubectl create token`. |

## Cleanup

```bash
kubectl delete namespace rbac-nginx-demo
```
