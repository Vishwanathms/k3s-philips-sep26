# Setup — Install Argo CD on k3s

**Prerequisite for stage 12 · ~30 min · do this once per cluster**

## Scenario

Both stage 12 labs — [this one](LAB-MANUAL.md) and
[Stage12-ArgoCD-local-git-repo](../Stage12-ArgoCD-local-git-repo/LAB-MANUAL.md)
— open with `kubectl -n argocd get pods` and assume something answers. This
manual is what makes that true: you install Argo CD, reach its UI, log in
with the CLI, secure the admin account, and leave the cluster in the exact
state stage 12 expects.

Argo CD is itself a Kubernetes application — a handful of Deployments and one
StatefulSet in their own namespace. Nothing here is special to k3s except how
you expose the UI, which uses the same Traefik Ingress you met in
[D3 ex02](../../D3-Networking/ex02-traefik-dashboard/LAB-MANUAL.md).

## Learning objectives

By the end you can:

- install Argo CD from pinned upstream manifests, and say what each component does
- explain why Argo CD needs a `StatefulSet` for its application controller
- retrieve the initial admin credential, and explain why it must not survive the lab
- expose a TLS-terminating service through Traefik, and why that needs `server.insecure`
- log in with the `argocd` CLI and explain what `--grpc-web` is working around
- confirm the cluster is ready for stage 12, including the kustomize/Helm setting it depends on

## Before starting

```bash
kubectl get nodes                  # Ready
kubectl get ingressclass           # traefik
kubectl cluster-info               # API server reachable
export NODE_IP=$(hostname -I | awk '{print $1}')
echo "$NODE_IP"
```

You also need outbound internet (the manifests and CLI come from GitHub) and
`sudo` on this node (to install the CLI binary and edit `/etc/hosts`).

**Already have Argo CD running?** Then skip to [A9](#a9--enable-the-helm-inflator-required-by-stage-12),
which is the one step the stage 12 manuals silently depend on. Check first:

```bash
kubectl -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

---

## A1 — Pin a version (2 min)

Never install from a moving target. `stable` is a branch that changes under
you; a tag does not, so two students installing a week apart get the same
cluster.

Find the current release and pin it:

```bash
export ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest \
  | grep -oP '"tag_name":\s*"\K[^"]+')
echo "$ARGOCD_VERSION"
```

Expected: a tag such as `v3.1.8` — the exact number depends on when you run
this. **Write it down**; step A7 installs a CLI that must match, and if you
ever rebuild this cluster you want the same one.

> If your instructor specified a version for the class, use theirs instead:
> `export ARGOCD_VERSION=v3.1.8`

## A2 — Install (5 min)

Argo CD installs into its own namespace, by convention called `argocd`. The
upstream manifest assumes that name — several ClusterRoleBindings reference
it — so don't rename it.

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f \
  "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
```

Expected: a long list of `created` lines — CRDs, ServiceAccounts, Roles,
ConfigMaps, Services, Deployments and one StatefulSet.

The three CRDs are the ones that matter to you:

```bash
kubectl get crd | grep argoproj
```

Expected:

```
applications.argoproj.io          ...
applicationsets.argoproj.io       ...
appprojects.argoproj.io           ...
```

`Application` is the object stage 12 creates. Argo CD is now an API extension
of your cluster: `kubectl get applications` is a real command.

## A3 — Wait for it, and read what you installed (5 min)

```bash
kubectl -n argocd wait --for=condition=Available deployment --all --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
kubectl -n argocd get pods
```

Expected — every Pod `Running`, every Deployment `1/1` (names and count vary
slightly by version):

```
NAME                                                READY   STATUS
argocd-application-controller-0                     1/1     Running
argocd-applicationset-controller-...                1/1     Running
argocd-dex-server-...                               1/1     Running
argocd-notifications-controller-...                 1/1     Running
argocd-redis-...                                    1/1     Running
argocd-repo-server-...                              1/1     Running
argocd-server-...                                   1/1     Running
```

| Component | Job |
|---|---|
| `argocd-application-controller` | The engine. Compares git (desired) against the cluster (live), and applies the difference. This is what "self-heal" actually is. |
| `argocd-repo-server` | Clones your git repo and **renders** it — runs `helm template` / `kustomize build`. Stage 12's `--enable-helm` setting is consumed here. |
| `argocd-server` | The API and web UI. Despite the name, it does no syncing. |
| `argocd-redis` | Cache of rendered manifests. Losing it costs performance, not state. |
| `argocd-dex-server` | SSO broker (GitHub, LDAP, OIDC). Unused in this course — see the footnote in A10 if your VM is tight on memory. |
| `argocd-applicationset-controller` | Generates many `Application`s from one template. Not used by stage 12. |
| `argocd-notifications-controller` | Sends Slack/email on sync events. Not used by stage 12. |

> **Why is the application controller a StatefulSet?** It shards work across
> replicas by *ordinal*, and each shard must keep its identity across
> restarts so two controllers never reconcile the same Application at once.
> A Deployment's random Pod names can't provide that — the same reasoning you
> saw behind redis in [D4 ex05](../../D4-Storage-/ex05-statefulset-storage/README.md).

> **Checkpoint A3:** all Pods `Running`, and you can say what
> `argocd-repo-server` does without looking.

## A4 — Get the initial admin password (2 min)

The install generates a random admin password and stores it in a Secret:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Expected: a 16-character random string. Keep this terminal open — you need it
twice below, and step A8 deletes it for good.

```bash
export ARGOCD_PW=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)
```

> This Secret is plain base64, not encryption — exactly as you saw with the
> Docker Hub credential in
> [LAB-MANUAL-Docker-Hub.md](../LAB-MANUAL-Docker-Hub.md) step A3. Anyone with
> read access to the `argocd` namespace has cluster-admin-by-proxy, because
> Argo CD itself holds broad permissions. That is why A8 is not optional.

## A5 — First look, via port-forward (3 min)

Before configuring anything, prove the server works. `port-forward` needs no
ingress, no DNS and no TLS decisions:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443 >/dev/null 2>&1 &
sleep 3
curl -sk https://localhost:8080/healthz; echo
```

Expected: `ok`

Open **https://localhost:8080** in a browser on this machine and log in as
`admin` with the password from A4. Your browser will warn about the
certificate — Argo CD generates a self-signed one at install. That's expected,
and A6 replaces this whole arrangement.

Then stop the forward:

```bash
kill %1
```

> **Checkpoint A5:** you have seen the Argo CD UI and logged in. It shows
> zero Applications — stage 12 creates the first one.

## A6 — Expose it properly through Traefik (8 min)

Port-forward dies with your terminal. For a URL that survives, put it behind
the same Ingress controller the rest of the course uses.

There's a wrinkle: `argocd-server` terminates TLS *itself* on port 443, so an
Ingress in front of it would mean TLS twice, and Traefik would get a
certificate error talking to the backend. The supported fix is to tell the
server to serve plain HTTP and let the Ingress own TLS:

```bash
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"server.insecure":"true"}}'
kubectl -n argocd rollout restart deployment argocd-server
kubectl -n argocd rollout status deployment argocd-server --timeout=120s
```

`argocd-cmd-params-cm` is the official place to set server flags — patching
the Deployment's `args` directly works too, but is overwritten the next time
someone re-applies the upstream manifest.

Now the Ingress:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
spec:
  ingressClassName: traefik
  rules:
    - host: argocd.k3s.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  name: http
EOF
```

Note `port.name: http`, not a number. The `argocd-server` Service exposes
both `http` (80) and `https` (443); naming it is unambiguous and survives the
Service being re-applied.

Verify without touching DNS:

```bash
curl -s -H 'Host: argocd.k3s.local' "http://$NODE_IP/healthz"; echo
```

Expected: `ok`

**For the browser**, add a hosts entry — `/etc/hosts` on Linux/macOS, or
`C:\Windows\System32\drivers\etc\hosts` as Administrator on Windows:

```
<NODE_IP>  argocd.k3s.local
```

Then open **http://argocd.k3s.local/** and log in as `admin`.

> **Checkpoint A6:** the UI loads over plain HTTP at `argocd.k3s.local` with
> no certificate warning, and `kubectl -n argocd get ingress` lists it.

> **Not production.** You have just put an admin console on plain HTTP. On a
> real cluster this Ingress carries TLS with a real certificate, and Argo CD
> sits behind SSO rather than a local admin account.

## A7 — Install the CLI and log in (5 min)

The UI is for watching; the CLI is for doing. Install the binary matching the
version you pinned in A1:

```bash
curl -sSL -o /tmp/argocd \
  "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
sudo install -m 555 /tmp/argocd /usr/local/bin/argocd
rm /tmp/argocd
argocd version --client
```

Expected: `argocd: v3.1.8+...` — matching `$ARGOCD_VERSION`.

Log in:

```bash
argocd login argocd.k3s.local --username admin --password "$ARGOCD_PW" --insecure --grpc-web
argocd account get-user-info
```

Expected:

```
'admin:login' logged in successfully
Logged In: true
Username: admin
Issuer: argocd
```

Two flags to understand rather than copy:

| Flag | Why |
|---|---|
| `--insecure` | you set `server.insecure` in A6, so the endpoint is plain HTTP. Without TLS there's no certificate for the CLI to validate. |
| `--grpc-web` | the CLI normally speaks gRPC over HTTP/2. Ingress controllers vary in how well they proxy that, so `--grpc-web` tunnels the same calls over ordinary HTTP/1.1. It is the standard flag for any Argo CD behind an ingress. |

> **Checkpoint A7:** `argocd app list` runs and prints an empty list — not an
> error. An empty list means authenticated and authorized.

## A8 — Secure the admin account (3 min)

The initial password has now been on your screen, in your shell history and
in an environment variable. Replace it, then destroy the Secret:

```bash
argocd account update-password        # prompts: current, then new (twice)
kubectl -n argocd delete secret argocd-initial-admin-secret
unset ARGOCD_PW
```

Expected: `Password updated`, `Context 'argocd.k3s.local' updated`, and
`secret "argocd-initial-admin-secret" deleted`.

Argo CD stores the bcrypt hash of the new password in `argocd-secret` and
never needs the initial Secret again. Deleting it is the documented step, not
a shortcut — leaving it behind means a credential nobody rotates sitting in
the namespace with the widest permissions in your cluster.

> **Checkpoint A8:** `kubectl -n argocd get secret argocd-initial-admin-secret`
> returns `NotFound`, and you can still `argocd app list` with the new
> password.

## A9 — Enable the Helm inflator (required by stage 12)

Stage 12's git repo is a `kustomization.yaml` that wraps a Helm chart with
`helmCharts:`. Argo CD's kustomize engine runs with that inflator **disabled**
by default, because an inline `helmCharts:` block makes kustomize shell out to
`helm`. Turn it on cluster-wide:

```bash
kubectl -n argocd patch cm argocd-cm --type merge \
  -p '{"data":{"kustomize.buildOptions":"--enable-helm"}}'
kubectl -n argocd rollout restart deployment argocd-repo-server
kubectl -n argocd rollout status deployment argocd-repo-server --timeout=120s
```

Confirm it stuck:

```bash
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.kustomize\.buildOptions}{"\n"}'
```

Expected: `--enable-helm`

> **Do not skip this.** Without it, stage 12's Application syncs to an empty
> render and reports `Synced` with nothing deployed, or fails with
> `must specify --enable-helm`. It is the single most common reason stage 12
> appears to do nothing. The local-git-repo manual sets it in its own step G2;
> **this GitHub manual does not**, so if you run stage 12b on a fresh cluster
> without this step, it will not work.

## A10 — Readiness check for stage 12

Everything [LAB-MANUAL.md](LAB-MANUAL.md) assumes, in one block:

```bash
kubectl -n argocd get pods --no-headers | grep -vc Running    # 0
kubectl get crd applications.argoproj.io -o name              # exists
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.kustomize\.buildOptions}{"\n"}'
argocd app list                                               # empty, no error
curl -s -H 'Host: argocd.k3s.local' "http://$NODE_IP/healthz" # ok
```

Expected: `0`, the CRD name, `--enable-helm`, an empty app list, and `ok`.

You can now run [LAB-MANUAL.md](LAB-MANUAL.md) from its **Before starting**
section.

> **Tight on memory?** `argocd-dex-server`, `argocd-applicationset-controller`
> and `argocd-notifications-controller` are unused by this course and can be
> scaled to zero, freeing roughly 200Mi:
>
> ```bash
> kubectl -n argocd scale deploy argocd-dex-server \
>   argocd-applicationset-controller argocd-notifications-controller --replicas=0
> ```
>
> Scale them back with `--replicas=1` if you later want SSO or ApplicationSets.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Pods stuck `Pending` | not enough CPU/memory on the node: `kubectl -n argocd describe pod <pod> \| tail -20`. Scale down the three unused components (A10) |
| `argocd-repo-server` `CrashLoopBackOff` | usually memory. `kubectl -n argocd logs deploy/argocd-repo-server --previous` |
| Browser: `ERR_TOO_MANY_REDIRECTS` at `argocd.k3s.local` | `server.insecure` was not applied, so the server still redirects to HTTPS behind an HTTP Ingress. Re-run A6 and confirm: `kubectl -n argocd get cm argocd-cmd-params-cm -o jsonpath='{.data.server\.insecure}'` |
| `404 page not found` from the Ingress | the hosts-file entry is missing, so the browser never sends `Host: argocd.k3s.local`. Test with `curl -H 'Host: ...'` first |
| CLI: `dial tcp ... connection refused` | you are pointed at the port-forward, which is gone. `argocd login argocd.k3s.local --insecure --grpc-web` |
| CLI: `rpc error: code = Unknown` or a hang on login | the `--grpc-web` flag is missing |
| `argocd login` says `Invalid username or password` | you changed it in A8; the initial Secret is gone by design. Reset: `argocd account update-password` needs the old one — if it is truly lost, `kubectl -n argocd patch secret argocd-secret -p '{"stringData":{"admin.password":"<bcrypt-hash>"}}'` |
| Stage 12 Application reports `Synced` but no Pods appear | A9 was skipped |
| `kubectl get applications` → `unknown resource` | the CRDs were not applied: re-run A2 and check `kubectl get crd \| grep argoproj` |

## Uninstall

Only if you want the cluster back the way it was. Delete Applications
**first** — an Application with `prune: true` will otherwise take its
workloads down with it in a way that is hard to read:

```bash
kubectl -n argocd delete applications --all
kubectl delete -n argocd -f \
  "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl delete namespace argocd
sudo rm -f /usr/local/bin/argocd
```

## What comes next

[LAB-MANUAL.md](LAB-MANUAL.md) — push the capstone chart to a private GitHub
repo, give Argo CD a deploy-key credential, and let it deploy and self-heal
the app from git.
