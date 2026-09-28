# ex06 — verified run

Captured **2026-09-08** on k3s `v1.36.4+k3s1` (client `v1.36.3`). Result:
**PASS** — manifests applied, the limited identity scaled its named Deployment,
deletion was denied, and the same permissions worked from a Pod with the
ServiceAccount's projected token.

## Apply and readiness

```console
$ kubectl apply -f ../00-namespace.yaml -f 01-nginx-deploy.yaml \
    -f 02-serviceaccount.yaml -f 03-role.yaml -f 04-rolebinding.yaml
namespace/d2-workloads-rbac created
deployment.apps/nginx-deploy created
serviceaccount/nginx-operator created
role.rbac.authorization.k8s.io/nginx-deployment-manager created
rolebinding.rbac.authorization.k8s.io/nginx-deployment-manager-binding created

$ kubectl rollout status deployment/nginx-deploy -n d2-workloads-rbac --timeout=120s
deployment "nginx-deploy" successfully rolled out

$ kubectl get deploy -n d2-workloads-rbac
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deploy   1/1     1            1           3s
```

## ServiceAccount behavior and RBAC

```console
$ kubectl get serviceaccount nginx-operator -n d2-workloads-rbac \
    -o jsonpath='{.secrets[*].name}{"\\n"}'

# Empty: current k3s/Kubernetes does not auto-create a token Secret.

$ kubectl auth can-i get deployment/nginx-deploy -n d2-workloads-rbac --as=system:serviceaccount:d2-workloads-rbac:nginx-operator
yes
$ kubectl auth can-i update deployment/nginx-deploy --subresource=scale -n d2-workloads-rbac --as=system:serviceaccount:d2-workloads-rbac:nginx-operator
yes
$ kubectl auth can-i list pods -n d2-workloads-rbac --as=system:serviceaccount:d2-workloads-rbac:nginx-operator
yes
$ kubectl auth can-i create deployments -n d2-workloads-rbac --as=system:serviceaccount:d2-workloads-rbac:nginx-operator
no
$ kubectl auth can-i delete deployment/nginx-deploy -n d2-workloads-rbac --as=system:serviceaccount:d2-workloads-rbac:nginx-operator
no

$ kubectl scale deployment/nginx-deploy --replicas=2 -n d2-workloads-rbac --as=system:serviceaccount:d2-workloads-rbac:nginx-operator
deployment.apps/nginx-deploy scaled
$ kubectl rollout status deployment/nginx-deploy -n d2-workloads-rbac --timeout=120s
deployment "nginx-deploy" successfully rolled out
$ kubectl get deployment nginx-deploy -n d2-workloads-rbac
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deploy   2/2     2            2           40s

$ kubectl delete deployment nginx-deploy -n d2-workloads-rbac --as=system:serviceaccount:d2-workloads-rbac:nginx-operator
Error from server (Forbidden): deployments.apps "nginx-deploy" is forbidden: User "system:serviceaccount:d2-workloads-rbac:nginx-operator" cannot delete resource "deployments" in API group "apps" in the namespace "d2-workloads-rbac"
```

## In-cluster projected-token test

```console
$ kubectl apply -f 05-operator-pod.yaml
pod/operator-box created
$ kubectl wait --for=condition=Ready pod/operator-box -n d2-workloads-rbac --timeout=120s
pod/operator-box condition met
$ kubectl exec -n d2-workloads-rbac operator-box -- kubectl auth can-i update deployment/nginx-deploy --subresource=scale
yes
$ kubectl exec -n d2-workloads-rbac operator-box -- kubectl auth can-i delete deployment/nginx-deploy
no
$ kubectl exec -n d2-workloads-rbac operator-box -- kubectl get deployment nginx-deploy
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deploy   1/1     1            1           2m34s
$ kubectl exec -n d2-workloads-rbac operator-box -- kubectl scale deployment/nginx-deploy --replicas=1
deployment.apps/nginx-deploy scaled
```

Also verified: `kubectl get deployments` from `operator-box` is `Forbidden`,
because the Role deliberately permits only the specifically named Deployment.

## Cleanup

```console
$ kubectl delete namespace d2-workloads-rbac --wait=true
namespace "d2-workloads-rbac" deleted
$ kubectl get namespace d2-workloads-rbac
Error from server (NotFound): namespaces "d2-workloads-rbac" not found
```
