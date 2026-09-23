# Lab Manual — RBAC for a real user, read-only Pod access (ex07)

**Goal:** create a genuine Kubernetes **User** identity for a person named
`alice` (not a ServiceAccount), and grant that user just enough RBAC to
**view Pods and their logs** in one namespace — nothing more.

**Cluster:** k3s `v1.36.4+k3s1`, single node (`lab-g2-vm2`).
**Duration:** ~15 minutes.
**Prerequisites:** an admin kubeconfig (`kubectl get nodes` works), `openssl`.

---

## Why a client certificate?

Kubernetes has no built-in user database. "Users" are asserted by
whatever the API server's authenticators accept — most commonly an x509
client certificate whose `CN` becomes the username and whose `O` fields
become group memberships. k3s trusts certificates signed by its own
client CA, and exposes that CA to `kubectl` through the
`CertificateSigningRequest` (CSR) API so you never have to touch the
CA's private key directly.

The workflow:

```
alice generates a keypair + CSR (CN=alice, O=developers)
        │
        ▼
CSR submitted as a CertificateSigningRequest object
        │
        ▼
cluster-admin approves it  ──►  k3s's controller signs it
        │
        ▼
signed certificate downloaded, wrapped in a kubeconfig
        │
        ▼
RBAC Role + RoleBinding grant "User alice" pod-read access
```

---

## Step 1 — Deploy the workload and RBAC objects

These are ordinary namespaced objects; no special identity is needed yet
because you're applying them as the cluster admin.

```bash
cd ex07-rbac-user-pod-access
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-demo-pods.yaml
kubectl apply -f 02-demo-secret.yaml
kubectl apply -f 03-role.yaml
kubectl apply -f 04-rolebinding.yaml
kubectl rollout status deployment/demo-app -n rbac-user-pod-demo --timeout=120s
```

`03-role.yaml` defines `pod-reader`:

```yaml
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
```

Note `pods/log` is its own sub-resource — granting `get` on `pods` does
**not** by itself allow `kubectl logs`.

`04-rolebinding.yaml` binds that Role to `kind: User, name: alice`. This
binding is created before alice's certificate even exists — RBAC only
cares about the *name* asserted at authentication time, so the order
doesn't matter.

## Step 2 — Create alice's private key and CSR

```bash
mkdir -p alice-identity
openssl genrsa -out alice-identity/alice.key 2048
openssl req -new -key alice-identity/alice.key -out alice-identity/alice.csr \
  -subj "/CN=alice/O=developers"
```

`CN=alice` becomes the Kubernetes username; `O=developers` becomes a
group (`system:authenticated` is added automatically). This lab binds
the Role to the **User**, not the group, but the group is there to show
it's available for a `GroupRoleBinding`-style design.

## Step 3 — Submit the CSR to the cluster and approve it

```bash
CSR_B64=$(base64 -w0 alice-identity/alice.csr)
cat > alice-identity/csr-alice.yaml <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: alice-csr
spec:
  request: ${CSR_B64}
  signerName: kubernetes.io/kube-apiserver-client
  usages:
    - client auth
EOF
kubectl apply -f alice-identity/csr-alice.yaml
kubectl get csr alice-csr          # CONDITION: Pending

kubectl certificate approve alice-csr
kubectl get csr alice-csr          # CONDITION: Approved,Issued
```

Approving a CSR requires the approver (here, the cluster admin) to have
RBAC permission on `certificatesigningrequests/approval` — this is a
deliberate choke point: nobody can hand themselves a certificate without
an admin's sign-off. k3s auto-signs the CSR the moment it's approved.

## Step 4 — Extract the signed certificate and build a kubeconfig

```bash
kubectl get csr alice-csr -o jsonpath='{.status.certificate}' \
  | base64 -d > alice-identity/alice.crt
openssl x509 -in alice-identity/alice.crt -noout -subject -issuer -dates

SERVER=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
  | base64 -d > alice-identity/ca.crt

KCFG=alice-identity/alice.kubeconfig
kubectl --kubeconfig="$KCFG" config set-cluster k3s-lab \
  --server="$SERVER" --certificate-authority=alice-identity/ca.crt --embed-certs=true
kubectl --kubeconfig="$KCFG" config set-credentials alice \
  --client-certificate=alice-identity/alice.crt --client-key=alice-identity/alice.key --embed-certs=true
kubectl --kubeconfig="$KCFG" config set-context alice@k3s-lab --cluster=k3s-lab --user=alice
kubectl --kubeconfig="$KCFG" config use-context alice@k3s-lab
```

Steps 2–4 are exactly what `scripts/create-user-alice.sh` automates —
run that script instead of typing all of the above by hand:

```bash
./scripts/create-user-alice.sh
```

## Step 5 — Confirm the identity

```bash
kubectl --kubeconfig=alice-identity/alice.kubeconfig auth whoami
```

Expect `Username: alice`, `Groups: [developers system:authenticated]`.

## Step 6 — Verify RBAC: allowed operations

```bash
KCFG=alice-identity/alice.kubeconfig
NS=rbac-user-pod-demo

kubectl --kubeconfig="$KCFG" get pods -n "$NS"
POD=$(kubectl get pods -n "$NS" -o jsonpath='{.items[0].metadata.name}')
kubectl --kubeconfig="$KCFG" logs "$POD" -n "$NS"
kubectl --kubeconfig="$KCFG" auth can-i --list -n "$NS"
```

## Step 7 — Verify RBAC: denied operations

```bash
kubectl --kubeconfig="$KCFG" get secret demo-secret -n "$NS"        # Forbidden — not in the Role
kubectl --kubeconfig="$KCFG" get deployment demo-app -n "$NS"       # Forbidden — not in the Role
kubectl --kubeconfig="$KCFG" delete pod "$POD" -n "$NS"             # Forbidden — no delete verb
kubectl --kubeconfig="$KCFG" exec -n "$NS" "$POD" -- ls /           # Forbidden — no pods/exec
kubectl --kubeconfig="$KCFG" get pods -n default                    # Forbidden — Role is namespaced to rbac-user-pod-demo
kubectl --kubeconfig="$KCFG" get pods -A                            # Forbidden — no ClusterRole
```

Each denial should name `User "alice"`, the verb, the resource, and the
namespace — that's the RBAC decision trail you'd read from
`kubectl describe rolebinding` plus the error itself when troubleshooting.

## Cleanup

```bash
./scripts/cleanup-user-alice.sh        # deletes CSR/alice-csr and alice-identity/
kubectl delete namespace rbac-user-pod-demo
```

---

## Troubleshooting

| Symptom | Check / fix |
|---|---|
| `kubectl certificate approve` is itself `Forbidden` | Your current context lacks `certificatesigningrequests/approval` — use the cluster-admin kubeconfig. |
| CSR stuck `Pending` after approval | k3s signs approved CSRs almost immediately; re-run `kubectl get csr alice-csr` after a couple of seconds. |
| `logs` denied but `get pods` allowed | The Role is missing the `pods/log` sub-resource rule — it is separate from `pods`. |
| Everything denied, including `get pods` | Confirm the RoleBinding's subject is `kind: User, name: alice` (exact match, case-sensitive) and its `roleRef` points at `pod-reader` in the **same namespace**. |
| `x509: certificate signed by unknown authority` | `alice.kubeconfig`'s `certificate-authority-data` doesn't match the server. Rebuild it from the current admin kubeconfig's CA data (Step 4). |
| Certificate works from one host but not another | The kubeconfig's `server` field is `https://127.0.0.1:6443` here (single-node lab, generated from the local admin config) — replace it with the node's real reachable IP if the kubeconfig is copied elsewhere. |
| Want this to expire sooner / rotate | x509 client certs from this signer are valid 1 year by default and are not renewed automatically; re-run the CSR flow to reissue. |
