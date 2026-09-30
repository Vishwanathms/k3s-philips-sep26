# Output — ex01 RBAC Best Practices

Real run against `lab-g2-vm2`, 2026-09-14.

## Audit: who already has cluster-admin on this real cluster

```
$ kubectl get clusterrolebindings -o json | jq -r '.items[] | select(.roleRef.name=="cluster-admin") |
  .metadata.name + " -> " + (.subjects // [] | map(.kind+":"+.name) | join(","))'
cluster-admin              -> Group:system:masters
helm-kube-system-traefik    -> ServiceAccount:helm-traefik
helm-kube-system-traefik-crd -> ServiceAccount:helm-traefik-crd
```

`system:masters` is the built-in break-glass admin group (this session's own
`~/.kube/config` is in it). The two `helm-*` bindings are k3s's own
bundled Helm install Jobs (they need cluster-admin briefly to install
Traefik's CRDs/chart, then the Job completes and the SA sits unused) — worth
knowing they exist, not necessarily worth removing on a single-purpose lab
cluster, but exactly the kind of finding a real RBAC audit should surface
and a production cluster should scope down or remove after install.

## The anti-pattern: a wildcard Role, in practice

```
$ kubectl apply -f overprivileged.yaml
serviceaccount/overprivileged-sa created
role.rbac.authorization.k8s.io/overprivileged-role created
rolebinding.rbac.authorization.k8s.io/overprivileged-binding created

$ kubectl auth can-i --list --as=system:serviceaccount:day11-security:overprivileged-sa -n day11-security
Resources   ...   Verbs
*.*         ...   [*]
```

```
$ kubectl auth can-i get secrets --as=system:serviceaccount:day11-security:overprivileged-sa -n day11-security
yes
```

`apiGroups: ["*"], resources: ["*"], verbs: ["*"]` in a **namespaced** Role
still means "read every Secret in this namespace, delete every Pod, patch
every Deployment" — anything that lands in this namespace's containers
would only need this token leaked once.

## The fix: exactly what the workload needs

```
$ kubectl apply -f least-privilege.yaml
serviceaccount/least-privilege-sa created
role.rbac.authorization.k8s.io/pod-reader created
rolebinding.rbac.authorization.k8s.io/pod-reader-binding created

$ kubectl auth can-i --list --as=system:serviceaccount:day11-security:least-privilege-sa -n day11-security
Resources   ...   Verbs
pods        ...   [get list watch]

$ kubectl auth can-i get secrets --as=system:serviceaccount:day11-security:least-privilege-sa -n day11-security
no
```

Same namespace, same kind of workload — but this token, even fully
compromised, can only ever list/watch/get Pods. It cannot read a Secret,
delete anything, or touch any other resource type.

## automountServiceAccountToken: the attack surface most Pods don't need

```
$ kubectl apply -f pod-no-automount.yaml
serviceaccount/no-api-access-sa created
pod/no-token-pod created

$ kubectl exec no-token-pod -n day11-security -- ls /var/run/secrets/kubernetes.io/serviceaccount/
ls: /var/run/secrets/kubernetes.io/serviceaccount/: No such file or directory
```

```
$ kubectl run default-sa-pod --image=busybox:1.36 -n day11-security --restart=Never --command -- sh -c "sleep 3600"
$ kubectl exec default-sa-pod -n day11-security -- ls /var/run/secrets/kubernetes.io/serviceaccount/
ca.crt
namespace
token
```

**Every Pod gets a live API token mounted by default**, whether it ever
calls the Kubernetes API or not — `default-sa-pod` (an ordinary busybox Pod
with no `serviceAccountName` set at all) has one sitting on disk right now.
`no-token-pod`'s ServiceAccount sets `automountServiceAccountToken: false`
— the exact same Pod spec, but there is nothing on disk for an attacker who
gets a shell in that container to steal. Most Pods never call the
Kubernetes API at all; this one line removes that entire attack surface for
free.

## Cleanup

```
$ kubectl delete -f overprivileged.yaml -f least-privilege.yaml -f pod-no-automount.yaml
$ kubectl delete pod default-sa-pod -n day11-security
```
