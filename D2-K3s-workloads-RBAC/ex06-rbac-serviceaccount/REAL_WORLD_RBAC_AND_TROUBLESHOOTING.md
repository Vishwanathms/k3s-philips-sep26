# Real-world RBAC design and troubleshooting (k3s)

This reference uses **namespace-scoped least privilege**: a person or workload
receives only the actions it needs, in only the namespace where it needs them.
It applies unchanged to k3s because k3s uses upstream Kubernetes RBAC.

## Design principles

- Prefer a `Role` + `RoleBinding` for application-team access inside one namespace.
- Use a `ClusterRole` only when permissions genuinely span namespaces or cover
  cluster-scoped resources; bind it with a `RoleBinding` when its permissions
  are still needed in only one namespace.
- Bind groups (for example `team-payments-devs`) rather than individual users.
- Separate human permissions from workload `ServiceAccount` permissions.
- Grant verbs narrowly. `get`, `list`, and `watch` are different permissions;
  `kubectl scale` requires the `deployments/scale` subresource.
- Avoid `cluster-admin` for routine team work. Review bindings and remove access
  when a team, application, or environment is retired.

## Scenario 1 — Product teams isolated by namespace

**Need:** Payments engineers manage only `payments-dev`; Orders engineers
manage only `orders-dev`. Platform administrators retain cluster ownership.

Create namespaces, then create one Role per team namespace. This role allows a
team to deploy and operate its applications, but it cannot read Secrets,
change RBAC, or access another team namespace.

```yaml
# payments-developer-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: application-developer
  namespace: payments-dev
rules:
  - apiGroups: ["", "apps"]
    resources: ["pods", "pods/log", "services", "configmaps", "deployments", "replicasets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments/scale"]
    verbs: ["get", "update", "patch"]
```

```yaml
# payments-developer-binding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: payments-developers
  namespace: payments-dev
subjects:
  - kind: Group
    name: team-payments-devs       # supplied by your OIDC/SSO identity provider
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: application-developer
  apiGroup: rbac.authorization.k8s.io
```

Apply the same Role shape in `orders-dev`, changing the namespace and group.
Do not use a single cross-namespace RoleBinding: Roles and RoleBindings are
namespace-scoped. This makes a namespace deletion and an access review simple.

## Scenario 2 — Read-only support across selected namespaces

**Need:** The SRE on-call group needs to inspect workloads, events, logs, and
rollout status in `payments-prod` and `orders-prod`, but must not edit them or
read Secrets.

Define a reusable ClusterRole, then create **one RoleBinding per approved
namespace**. A ClusterRole does not force a cluster-wide grant; the binding
scope controls where it applies.

```yaml
# support-observer-clusterrole.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: support-observer
rules:
  - apiGroups: ["", "apps", "batch"]
    resources: ["pods", "pods/log", "services", "endpoints", "events", "deployments", "replicasets", "statefulsets", "daemonsets", "jobs", "cronjobs"]
    verbs: ["get", "list", "watch"]
```

```yaml
# payments-prod-support-binding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: support-observers
  namespace: payments-prod
subjects:
  - kind: Group
    name: group-sre-oncall
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: support-observer
  apiGroup: rbac.authorization.k8s.io
```

Repeat the binding for `orders-prod`. Do **not** use a ClusterRoleBinding unless
the group truly needs the role in every current and future namespace.

## Scenario 3 — CI/CD ServiceAccount for one application

**Need:** A CI pipeline deploys `catalog-api` only in `catalog-staging`. It
must update that Deployment and its image, read rollout state, and not manage
other workloads.

Use a dedicated ServiceAccount, name-limit the Deployment rules, and bind it
within the application namespace.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: catalog-deployer
  namespace: catalog-staging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: catalog-api-deployer
  namespace: catalog-staging
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    resourceNames: ["catalog-api"]
    verbs: ["get", "update", "patch"]
  - apiGroups: ["apps"]
    resources: ["deployments/scale"]
    resourceNames: ["catalog-api"]
    verbs: ["get", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: catalog-api-deployer
  namespace: catalog-staging
subjects:
  - kind: ServiceAccount
    name: catalog-deployer
    namespace: catalog-staging
roleRef:
  kind: Role
  name: catalog-api-deployer
  apiGroup: rbac.authorization.k8s.io
```

Name-limited rules intentionally do not grant `list deployments`. Pipeline
commands should address the object by name, such as
`kubectl rollout status deployment/catalog-api`.

## Scenario 4 — Shared platform services

**Need:** A platform group manages Ingress, ResourceQuota, LimitRange, and
NetworkPolicy in every application namespace. Application teams cannot alter
those guardrails.

Create a `ClusterRole` for exactly those platform APIs and RoleBind it only in
the namespaces that are enrolled. Keep the ownership boundary explicit:

| Team owns | Platform owns |
|---|---|
| Deployments, Services, app ConfigMaps | Namespace creation and labels |
| Application rollout and logs | ResourceQuota and LimitRange |
| App-specific NetworkPolicy requests | Ingress controller and shared ingress configuration |
| Their own namespace RoleBindings only if required | ClusterRoles, ClusterRoleBindings, CRDs, nodes |

Avoid giving app teams write access to `roles`, `rolebindings`,
`clusterroles`, or `clusterrolebindings`: that can become privilege escalation.

## Troubleshooting RBAC and permission issues

### 1. Identify the actual identity and namespace

```bash
kubectl config current-context
kubectl auth whoami                         # supported by current kubectl/k3s
kubectl config view --minify
kubectl get pod <pod> -n <namespace> -o jsonpath='{.spec.serviceAccountName}{"\n"}'
```

For a ServiceAccount, the username format is:

```text
system:serviceaccount:<namespace>:<serviceaccount>
```

### 2. Ask the API server, not guesswork

```bash
# Human or CI identity using its current kubeconfig
kubectl auth can-i patch deployment/catalog-api -n catalog-staging

# Check a ServiceAccount while logged in as an administrator
kubectl auth can-i patch deployment/catalog-api -n catalog-staging \
  --as=system:serviceaccount:catalog-staging:catalog-deployer

# A subresource must be tested explicitly
kubectl auth can-i update deployment/catalog-api --subresource=scale \
  -n catalog-staging --as=system:serviceaccount:catalog-staging:catalog-deployer
```

### 3. Inspect bindings before changing permissions

```bash
kubectl get rolebinding -n catalog-staging
kubectl describe rolebinding catalog-api-deployer -n catalog-staging
kubectl describe role catalog-api-deployer -n catalog-staging
kubectl get clusterrolebinding
```

Confirm all of these match: binding namespace, subject kind/name/namespace,
`roleRef` kind/name, API group, resource, verb, and subresource.

### Common failures

| Symptom | Likely cause | Fix |
|---|---|---|
| `User ... cannot get resource ...` | Wrong namespace, missing verb, or missing binding | Use `kubectl auth can-i`, then correct the Role and binding in that namespace. |
| `kubectl scale` is Forbidden but patch works | `deployments/scale` is absent | Add an explicit `deployments/scale` rule. |
| `kubectl logs` is Forbidden | `pods/log` is a subresource | Grant `get` on `pods/log`, not only `pods`. |
| `exec` is Forbidden | `pods/exec` is a subresource; it is powerful | Grant `create` on `pods/exec` only where justified. |
| ServiceAccount token Secret is missing | Expected on Kubernetes 1.24+ | Use a projected token in a Pod or `kubectl create token <sa> -n <ns>`. |
| `--as` is Forbidden | Your troubleshooting identity cannot impersonate | Use an approved admin identity or test inside a Pod using the ServiceAccount. |
| A user can access every namespace | A ClusterRoleBinding is broader than intended | Replace it with namespace-specific RoleBindings. |
| A RoleBinding "does nothing" | It references a Role in a different namespace or wrong subject | Recreate it in the target namespace and verify the exact subject. |

### Safe investigation order

1. Record the exact `Forbidden` message, API resource, verb, and namespace.
2. Identify the requesting user or ServiceAccount.
3. Run the matching `kubectl auth can-i` query.
4. Inspect the relevant Role/ClusterRole and RoleBinding/ClusterRoleBinding.
5. Add the smallest missing permission; do not “fix” it with `cluster-admin`.
6. Re-run the original command and retain the result in the change record.

## Review checklist

```bash
kubectl get role,rolebinding -A
kubectl get clusterrole,clusterrolebinding
kubectl auth can-i --list -n <namespace>
```

Review at least quarterly and after team changes. Look especially for wildcard
verbs/resources, `cluster-admin` bindings, unused ServiceAccounts, direct
individual-user bindings, and access to Secrets or RBAC resources.
