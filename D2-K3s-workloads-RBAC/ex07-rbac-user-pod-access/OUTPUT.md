# ex07 — verified run

Captured **2026-09-23** on k3s `v1.36.4+k3s1` (client `v1.36.3`), single
node `lab-g2-vm2`. Result: **PASS** — a real x509-authenticated Kubernetes
`User` (`alice`) was created via the `CertificateSigningRequest` API,
granted read-only Pod access in one namespace, and every allowed/denied
operation matched the Role exactly, including `kubectl auth whoami` and
`auth can-i --list` matching the Role's rules 1:1.

## Apply the namespace, workload, and RBAC objects

```console
$ kubectl apply -f 00-namespace.yaml -f 01-demo-pods.yaml -f 02-demo-secret.yaml \
    -f 03-role.yaml -f 04-rolebinding.yaml
namespace/rbac-user-pod-demo created
deployment.apps/demo-app created
secret/demo-secret created
role.rbac.authorization.k8s.io/pod-reader created
rolebinding.rbac.authorization.k8s.io/pod-reader-binding created

$ kubectl rollout status deployment/demo-app -n rbac-user-pod-demo --timeout=120s
Waiting for deployment "demo-app" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "demo-app" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "demo-app" rollout to finish: 1 of 2 updated replicas are available...
deployment "demo-app" successfully rolled out

$ kubectl get deploy,pods,role,rolebinding,secret -n rbac-user-pod-demo
NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/demo-app   2/2     2            2           4s

NAME                           READY   STATUS    RESTARTS   AGE
pod/demo-app-b8cc868df-d2cz7   1/1     Running   0          4s
pod/demo-app-b8cc868df-z5zrs   1/1     Running   0          4s

NAME                                        CREATED AT
role.rbac.authorization.k8s.io/pod-reader   2026-09-23T06:18:46Z

NAME                                                       ROLE              AGE
rolebinding.rbac.authorization.k8s.io/pod-reader-binding   Role/pod-reader   5s

NAME                 TYPE     DATA   AGE
secret/demo-secret   Opaque   1      5s
```

## Create the user identity — `scripts/create-user-alice.sh`

Ran the actual script (not just the manual steps) to confirm it works
end-to-end and is reproducible:

```console
$ ./scripts/create-user-alice.sh
==> Generating private key + CSR for CN=alice
==> Submitting CertificateSigningRequest/alice-csr
certificatesigningrequest.certificates.k8s.io/alice-csr created
==> Approving alice-csr (requires cluster-admin)
certificatesigningrequest.certificates.k8s.io/alice-csr approved
==> Waiting for the signed certificate
subject=O = developers, CN = alice
issuer=CN = k3s-client-ca@1788848191
notBefore=Sep 23 06:14:57 2026 GMT
notAfter=Sep 23 06:14:57 2027 GMT
==> Building alice.kubeconfig
Cluster "k3s-lab" set.
User "alice" set.
Context "alice@k3s-lab" created.
Switched to context "alice@k3s-lab".
==> Done. Use it with:
    kubectl --kubeconfig=alice-identity/alice.kubeconfig <command>
    export KUBECONFIG=/home/labuser/Documents/k3s-training/Day-02-RBAC-ServiceAccount/ex07-rbac-user-pod-access/alice-identity/alice.kubeconfig   # or switch entirely
```

`CN=alice` / `O=developers` round-tripped correctly through the CSR, and
k3s signed it for 1 year immediately on approval — confirming k3s does
**not** auto-approve `kubernetes.io/kube-apiserver-client` CSRs; the
`kubectl certificate approve` step is required.

## Confirm the identity

```console
$ kubectl --kubeconfig=alice-identity/alice.kubeconfig auth whoami
ATTRIBUTE                                           VALUE
Username                                            alice
Groups                                              [developers system:authenticated]
Extra: authentication.kubernetes.io/credential-id   [X509SHA256=8238b2bf6cf171a5cc47961bdff28c9e102534662cd1b58f94c520ab55c16375]
```

The API server is authenticating the client certificate exactly as
designed: username from `CN`, group from `O`, plus the implicit
`system:authenticated` group.

## Verify RBAC — allowed

```console
$ KCFG=alice-identity/alice.kubeconfig; NS=rbac-user-pod-demo

$ kubectl --kubeconfig="$KCFG" get pods -n "$NS"
NAME                       READY   STATUS    RESTARTS   AGE
demo-app-b8cc868df-d2cz7   1/1     Running   0          37s
demo-app-b8cc868df-z5zrs   1/1     Running   0          37s

$ kubectl --kubeconfig="$KCFG" logs demo-app-b8cc868df-d2cz7 -n "$NS"
/docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
/docker-entrypoint.sh: Looking for shell scripts in /docker-entrypoint.d/
/docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
10-listen-on-ipv6-by-default.sh: info: Getting the checksum of /etc/nginx/conf.d/default.conf
10-listen-on-ipv6-by-default.sh: info: Enabled listen on IPv6 in /etc/nginx/conf.d/default.conf

$ kubectl --kubeconfig="$KCFG" auth can-i --list -n "$NS"
Resources                                       Non-Resource URLs   Resource Names   Verbs
selfsubjectreviews.authentication.k8s.io        []                  []               [create]
selfsubjectaccessreviews.authorization.k8s.io   []                  []               [create]
selfsubjectrulesreviews.authorization.k8s.io    []                  []               [create]
pods                                            []                  []               [get list watch]
                                                 [/api/*]            []               [get]
                                                 ... (standard discovery/healthz/openapi/version endpoints, [get])
pods/log                                        []                  []               [get]
```

`auth can-i --list` shows exactly `pods` (`get list watch`) and
`pods/log` (`get`) as resource permissions — nothing else, which is the
Role verbatim. The `selfsubject*review` and discovery entries are
granted to every authenticated user by a built-in ClusterRoleBinding, not
by `pod-reader`.

## Verify RBAC — denied

```console
$ kubectl --kubeconfig="$KCFG" get secret demo-secret -n "$NS"
Error from server (Forbidden): secrets "demo-secret" is forbidden: User "alice" cannot get resource "secrets" in API group "" in the namespace "rbac-user-pod-demo"

$ kubectl --kubeconfig="$KCFG" get deployment demo-app -n "$NS"
Error from server (Forbidden): deployments.apps "demo-app" is forbidden: User "alice" cannot get resource "deployments" in API group "apps" in the namespace "rbac-user-pod-demo"

$ kubectl --kubeconfig="$KCFG" delete pod demo-app-b8cc868df-d2cz7 -n "$NS"
Error from server (Forbidden): pods "demo-app-b8cc868df-d2cz7" is forbidden: User "alice" cannot delete resource "pods" in API group "" in the namespace "rbac-user-pod-demo"

$ kubectl --kubeconfig="$KCFG" exec -n "$NS" demo-app-b8cc868df-d2cz7 -- ls /
error: unable to upgrade connection: pods "demo-app-b8cc868df-d2cz7" is forbidden: User "alice" cannot create resource "pods/exec" in API group "" in the namespace "rbac-user-pod-demo"

$ kubectl --kubeconfig="$KCFG" get pods -A
Error from server (Forbidden): pods is forbidden: User "alice" cannot list resource "pods" in API group "" at the cluster scope

$ kubectl --kubeconfig="$KCFG" get pods -n default
Error from server (Forbidden): pods is forbidden: User "alice" cannot list resource "pods" in API group "" in the namespace "default"
```

Every denial correctly names `User "alice"` (not a ServiceAccount), the
exact verb, resource, API group, and scope. Secrets and Deployments are
denied because they're simply absent from the Role. Cluster-wide listing
(`-A`) and the `default` namespace are denied because the RoleBinding is
namespaced to `rbac-user-pod-demo` only — a Role/RoleBinding never
grants cluster-wide access, unlike a ClusterRole/ClusterRoleBinding.

## `auth can-i` matrix (re-run against a freshly regenerated identity)

Re-ran `cleanup-user-alice.sh` + `create-user-alice.sh` and re-checked
with `auth can-i` (non-interactive form) to confirm the result is
reproducible, not a one-off:

```console
$ kubectl --kubeconfig="$KCFG" auth can-i get pods -n "$NS"       ; yes
$ kubectl --kubeconfig="$KCFG" auth can-i list pods -n "$NS"      ; yes
$ kubectl --kubeconfig="$KCFG" auth can-i get pods/log -n "$NS"   ; yes
$ kubectl --kubeconfig="$KCFG" auth can-i create pods -n "$NS"    ; no
$ kubectl --kubeconfig="$KCFG" auth can-i delete pods -n "$NS"    ; no
$ kubectl --kubeconfig="$KCFG" auth can-i create pods/exec -n "$NS" ; no
$ kubectl --kubeconfig="$KCFG" auth can-i get secrets -n "$NS"    ; no
$ kubectl --kubeconfig="$KCFG" auth can-i get deployments -n "$NS"; no
$ kubectl --kubeconfig="$KCFG" auth can-i list pods -n default    ; no
```

Identical result to the first run.

## Cleanup

```console
$ kubectl delete namespace rbac-user-pod-demo --wait=true
namespace "rbac-user-pod-demo" deleted
$ kubectl get namespace rbac-user-pod-demo
Error from server (NotFound): namespaces "rbac-user-pod-demo" not found

$ ./scripts/cleanup-user-alice.sh
certificatesigningrequest.certificates.k8s.io "alice-csr" deleted
==> Removed CSR/alice-csr and alice-identity/
$ ls alice-identity
ls: cannot access 'alice-identity': No such file or directory
```

Namespace, workload, RBAC objects, the CSR object, and alice's locally
generated key/cert/kubeconfig were all removed. Nothing from this
exercise remains on the cluster or on disk.
