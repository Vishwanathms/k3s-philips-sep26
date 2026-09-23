# ex06 — verified run

Captured **2026-09-08** on k3s `v1.36.4+k3s1` (client `v1.36.3`). Result:
**PASS** — manifests applied, the limited identity scaled its named Deployment,
deletion was denied, and the same permissions worked from a Pod with the
ServiceAccount's projected token.

## Apply and readiness

```console
$ kubectl apply -f 00-namespace.yaml -f 01-nginx-deploy.yaml \
    -f 02-serviceaccount.yaml -f 03-role.yaml -f 04-rolebinding.yaml
namespace/rbac-nginx-demo created
deployment.apps/nginx-deploy created
serviceaccount/nginx-operator created
role.rbac.authorization.k8s.io/nginx-deployment-manager created
rolebinding.rbac.authorization.k8s.io/nginx-deployment-manager-binding created

$ kubectl rollout status deployment/nginx-deploy -n rbac-nginx-demo --timeout=120s
deployment "nginx-deploy" successfully rolled out

$ kubectl get deploy -n rbac-nginx-demo
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deploy   1/1     1            1           3s
```

## ServiceAccount behavior and RBAC

```console
$ kubectl get serviceaccount nginx-operator -n rbac-nginx-demo \
    -o jsonpath='{.secrets[*].name}{"\\n"}'

# Empty: current k3s/Kubernetes does not auto-create a token Secret.

$ kubectl auth can-i get deployment/nginx-deploy -n rbac-nginx-demo --as=system:serviceaccount:rbac-nginx-demo:nginx-operator
yes
$ kubectl auth can-i update deployment/nginx-deploy --subresource=scale -n rbac-nginx-demo --as=system:serviceaccount:rbac-nginx-demo:nginx-operator
yes
$ kubectl auth can-i list pods -n rbac-nginx-demo --as=system:serviceaccount:rbac-nginx-demo:nginx-operator
yes
$ kubectl auth can-i create deployments -n rbac-nginx-demo --as=system:serviceaccount:rbac-nginx-demo:nginx-operator
no
$ kubectl auth can-i delete deployment/nginx-deploy -n rbac-nginx-demo --as=system:serviceaccount:rbac-nginx-demo:nginx-operator
no

$ kubectl scale deployment/nginx-deploy --replicas=2 -n rbac-nginx-demo --as=system:serviceaccount:rbac-nginx-demo:nginx-operator
deployment.apps/nginx-deploy scaled
$ kubectl rollout status deployment/nginx-deploy -n rbac-nginx-demo --timeout=120s
deployment "nginx-deploy" successfully rolled out
$ kubectl get deployment nginx-deploy -n rbac-nginx-demo
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deploy   2/2     2            2           40s

$ kubectl delete deployment nginx-deploy -n rbac-nginx-demo --as=system:serviceaccount:rbac-nginx-demo:nginx-operator
Error from server (Forbidden): deployments.apps "nginx-deploy" is forbidden: User "system:serviceaccount:rbac-nginx-demo:nginx-operator" cannot delete resource "deployments" in API group "apps" in the namespace "rbac-nginx-demo"
```

## In-cluster projected-token test

```console
$ kubectl apply -f 05-operator-pod.yaml
pod/operator-box created
$ kubectl wait --for=condition=Ready pod/operator-box -n rbac-nginx-demo --timeout=120s
pod/operator-box condition met
$ kubectl exec -n rbac-nginx-demo operator-box -- kubectl auth can-i update deployment/nginx-deploy --subresource=scale
yes
$ kubectl exec -n rbac-nginx-demo operator-box -- kubectl auth can-i delete deployment/nginx-deploy
no
$ kubectl exec -n rbac-nginx-demo operator-box -- kubectl get deployment nginx-deploy
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deploy   1/1     1            1           2m34s
$ kubectl exec -n rbac-nginx-demo operator-box -- kubectl scale deployment/nginx-deploy --replicas=1
deployment.apps/nginx-deploy scaled
```

Also verified: `kubectl get deployments` from `operator-box` is `Forbidden`,
because the Role deliberately permits only the specifically named Deployment.

## Cleanup

```console
$ kubectl delete namespace rbac-nginx-demo --wait=true
namespace "rbac-nginx-demo" deleted
$ kubectl get namespace rbac-nginx-demo
Error from server (NotFound): namespaces "rbac-nginx-demo" not found
```
