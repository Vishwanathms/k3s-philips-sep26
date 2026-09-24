# Day 02 Assignment — Workloads, Configuration & RBAC on k3s

**Level:** Intermediate → Advanced
**Suggested effort:** 4–6 hours
**Environment:** your own k3s cluster (single node is fine). You need `kubectl`, `openssl`, and shell access to the k3s **server** node.

---

## Scope

Everything in this assignment is built from Day 01 and Day 02 material only:

| Source | What it gives you |
|---|---|
| `PPT1-Kubernetes_Workloads.pdf` | Pods, ReplicaSets, Deployments, StatefulSets, DaemonSets, Jobs, CronJobs, init containers, sidecars, lifecycle hooks, startup/shutdown behaviour |
| [D1 ex01 — nginx](../../D1-Docker-kube-k3s-Intro/ex01-nginx/LAB-MANUAL.md) | Deployment → ReplicaSet → Pod, Service, endpoints |
| [D1 ex02 — python + redis](../../D1-Docker-kube-k3s-Intro/ex02-python-redis/LAB-MANUAL.md) | two workloads talking over a Service, reaching a dependency by name |
| [ex03](../ex03-env-redis-host/README.md) · [ex04](../ex04-configmap/README.md) · [ex05](../ex05-dockerhub-secret/README.md) | env vars → ConfigMap → Secret, `imagePullSecrets` |
| [ex06](../ex06-rbac-serviceaccount/README.md) · [ex07](../ex07-rbac-user-pod-access/README.md) | ServiceAccount RBAC, x509 human-user RBAC |
| [Real-world RBAC design & troubleshooting](../ex06-rbac-serviceaccount/REAL_WORLD_RBAC_AND_TROUBLESHOOTING.md) | multi-team Role/ClusterRole design, troubleshooting method |

> **Deliberately out of scope — don't go there.** Service types and headless Services, DNS internals, Ingress, PersistentVolumes/PVCs and StorageClasses, resource requests/limits and quotas, scheduling (affinity, taints, tolerations), autoscaling, and Helm. Several of these get name-checked on a slide — that's a forward reference, not an invitation. Use a plain Service only as plumbing, exactly the way D1 ex02 does, and nothing more.

---

## Scenario

You are the platform engineer for **Acme Imaging**, a medical-imaging SaaS running on k3s. Two application teams and one operations group share the cluster:

| Group | Needs |
|---|---|
| **Ingest team** | Owns the scan-ingest pipeline. Deploys and operates workloads in `imaging-dev`. |
| **Reporting team** | Owns the reporting API. Same rights, but only in `imaging-prod`. |
| **SRE on-call** | Must triage incidents in **both** namespaces — read-only, and must never read Secrets. |
| **CI pipeline** | Deploys exactly one Deployment (`report-api`) in `imaging-dev`. Nothing else. |
| **Dr. Patel (auditor)** | An external clinical auditor. Read-only view of Pods and their logs in `imaging-prod` only. Has no company SSO account. |

Build the workloads this platform runs on, configure them without baking values into images, then lock the cluster down so each group has *exactly* the access it needs — no more.

> **Ground rule — least privilege.** Solve nothing with `cluster-admin`, a wildcard (`*`) verb or resource, or a `ClusterRoleBinding` where a `RoleBinding` would do. The permissions you *withhold* matter as much as the ones you grant — a task where the commands succeed but the boundary was never established is not finished.

---

## What you produce

A single directory (or git repo) named `day02-assignment-<yourname>/`, laid out like the course exercises:

```
day02-assignment-<yourname>/
├── README.md              # your written answers (the "Explain" prompts + Part E)
├── OUTPUT.md              # captured commands + real output, in the style of the ex0*/OUTPUT.md files
├── partA-workloads/
├── partB-config/
├── partC-rbac/
└── partD-fixes/
```

**`OUTPUT.md` is the record of your work.** Follow the format of [ex07's OUTPUT.md](../ex07-rbac-user-pod-access/OUTPUT.md): real pasted terminal output, including the failures you were *supposed* to trigger. Capturing output is what forces you to actually observe the behaviour instead of assuming it.

**Never commit a private key, a kubeconfig with embedded credentials, or a registry token.** A `.gitignore` is provided.

---

## Part A — Workloads

Work in namespace `imaging-dev`. Declarative YAML only — no bare `kubectl create deployment`.

### A1. ReplicaSet self-healing, and who really owns the Pods

Create a bare **ReplicaSet** named `ingest-rs` (3 replicas, any small image). Then:

- Delete one Pod directly and capture the replacement being created.
- Change one surviving Pod's `app` label so it no longer matches the ReplicaSet's `selector`, and observe what the ReplicaSet does.

**Explain in `README.md`:** what happened to the relabelled Pod and why — what is the ReplicaSet actually counting? Tie this back to the Deployment → ReplicaSet → Pod chain you saw in [D1 ex01](../../D1-Docker-kube-k3s-Intro/ex01-nginx/LAB-MANUAL.md).

### A2. Deployment rollout and rollback

Deploy `report-api` (use `vishwacloudlab/pythonapp:v4-var`, or any image you like) as a **Deployment** with 3 replicas, reachable through a Service the way D1 ex02 does it.

- Update the image and capture the rolling update in progress — show both ReplicaSets coexisting, one scaling up while the other scales down.
- Roll it back with `kubectl rollout undo` and show the revision history.

**Explain in `README.md`:** what the old ReplicaSet is kept around for after a successful rollout, and how `rollout undo` uses it.

### A3. StatefulSet — ordered, identity-preserving

Deploy Redis as a **StatefulSet** named `redis` with 2 replicas (`redis:7-alpine`). Use an `emptyDir` volume — per-replica persistent storage is a later topic and is not required here.

- Capture the Pods being **created in order** (`redis-0` before `redis-1`).
- Scale to 3, then back to 1, and capture the **termination order**.
- Delete `redis-0` and show what name the replacement comes back with.

**Explain in `README.md`:** how a StatefulSet's Pod identity differs from a Deployment's, and name one concrete thing that breaks if you run Redis as a Deployment with 2 replicas instead.

### A4. DaemonSet

Deploy a **DaemonSet** named `node-agent` that runs one Pod per node (a `busybox` running `sleep` is fine).

Show what `kubectl get daemonset` reports for `DESIRED` / `CURRENT` on your cluster.

**Explain in `README.md`:** where that `DESIRED` number comes from — you never wrote a replica count anywhere — and what would happen to it if a second node joined the cluster.

### A5. Job and CronJob

- A **Job** named `db-migrate` that runs to completion, with `backoffLimit` set deliberately. Show the Pod reaching `Completed` and the Job reporting `COMPLETIONS 1/1`.
- Make a second Job that **fails on purpose** (exit non-zero) and capture the retry behaviour your `backoffLimit` produces.
- A **CronJob** named `nightly-report` scheduled at 02:15 daily, with an explicit `concurrencyPolicy` and `successfulJobsHistoryLimit`.

**Demonstrate:** trigger the CronJob immediately rather than waiting for 02:15 (`kubectl create job --from=cronjob/nightly-report ...`) and show the resulting Job complete.

**Explain in `README.md`:** which `concurrencyPolicy` you chose, and the real-world consequence of `Allow` for a report that writes to a shared database.

### A6. Init container, sidecar, and the shutdown sequence

Add to your `report-api` Deployment, **all** of:

- An **init container** that blocks until Redis is accepting connections (the `until nc -z redis 6379; do sleep 2; done` pattern) — the app container must not start before Redis is up.
- A **sidecar container** that tails a file the main container writes, sharing it via an `emptyDir`.
- A **`postStart`** hook and a **`preStop`** hook, plus a `terminationGracePeriodSeconds` you chose deliberately.
- A **`readinessProbe`**, so the Pod only receives traffic once it's actually ready.

**Demonstrate in `OUTPUT.md`:**

- The init container holding the Pod at `Init:0/1` — scale Redis to 0 first to force it, then scale it back and show the app proceed.
- The `preStop` hook firing during a `kubectl delete pod`.

**Explain in `README.md`:** walk through the five-step shutdown sequence from the deck for one of your Pods, and say specifically at which step the Pod stops receiving new traffic — and why that happens *before* SIGTERM rather than after.

---

## Part B — Configuration

### B1. From env var to ConfigMap

Start from the [ex03](../ex03-env-redis-host/README.md) pattern (`REDIS_HOST` hardcoded in the Pod spec), then move it into a ConfigMap `report-api-config` as in [ex04](../ex04-configmap/README.md).

Consume that ConfigMap **both** ways in the same Pod spec:

- `REDIS_HOST` and `LOG_LEVEL` as environment variables, and
- a config file (e.g. `app.properties`) mounted as a volume.

Change a value in the ConfigMap and demonstrate the difference in `OUTPUT.md`: one consumption method picks the change up without a restart, the other does not. Show both, and give the command needed for the one that doesn't.

**Explain in `README.md`:** why the two behave differently.

### B2. Secret

Create a Secret `report-api-secrets` holding `REDIS_PASSWORD`, consumed via `secretKeyRef`.

- Show that base64 is **encoding, not encryption**, by recovering the value from `kubectl get secret -o yaml`.
- **Explain in `README.md`:** two concrete controls that actually protect this value in a real cluster. One of them is something you build in Part C — name which.

> **Optional extension:** create a `kubernetes.io/dockerconfigjson` Secret and attach it with `imagePullSecrets`, showing the pull authenticated ([ex05](../ex05-dockerhub-secret/README.md)). Needs a Docker Hub account — use an **access token**, never a password, and don't commit it.

---

## Part C — RBAC design

Read [REAL_WORLD_RBAC_AND_TROUBLESHOOTING.md](../ex06-rbac-serviceaccount/REAL_WORLD_RBAC_AND_TROUBLESHOOTING.md) before starting. Create `imaging-prod` as well as `imaging-dev`.

For **every** grant below, capture both a passing and a failing `kubectl auth can-i` in `OUTPUT.md`. Establishing where a permission *stops* is the substance of this part — a grant you haven't tested the edge of is one you don't yet understand.

### C1. CI pipeline ServiceAccount

A ServiceAccount `ci-deployer` in `imaging-dev` that can:

- read, update and patch **only** the Deployment named `report-api`,
- run `kubectl scale` against it,
- read Pods to watch the rollout.

It must **not** create or delete Deployments, touch any other Deployment, or read Secrets.

Prove the boundary — including that `kubectl get deployments` (plural, unnamed) is denied.

**Explain in `README.md`:** why that plural denial is expected behaviour rather than a bug, and why `kubectl scale` needed a rule you'd never guess from the verb name alone.

### C2. Human user via x509 client certificate

Create a real user identity `dr-patel` (`CN=dr-patel`, `O=auditors`) through the cluster's CSR API, following [ex07](../ex07-rbac-user-pod-access/LAB-MANUAL.md).

Grant read-only access to **Pods and Pod logs in `imaging-prod` only**.

Demonstrate using a kubeconfig that authenticates *as* `dr-patel` — not `--as` impersonation, which skips the authentication half of the lesson:

- `kubectl auth whoami` returns `dr-patel`,
- listing Pods and reading logs in `imaging-prod` succeeds,
- reading a **Secret** is Forbidden,
- `kubectl exec` is Forbidden,
- the same commands against `imaging-dev` are Forbidden.

**Explain in `README.md`:** Dr. Patel's engagement ends. Describe exactly how you revoke this access, and why deleting the RoleBinding is not the same thing as revoking the *certificate*.

### C3. One ClusterRole, two namespaces

SRE on-call needs identical read-only triage rights (Pods, Pod logs, events, Deployments, ReplicaSets, Jobs) in **both** `imaging-dev` and `imaging-prod` — and nowhere else, now or in future.

Implement with **one `ClusterRole` and two `RoleBinding`s**, bound to the Group `group-sre-oncall`.

**Explain in `README.md`:** why a `ClusterRoleBinding` is the wrong tool here, and what silently goes wrong the day someone creates a `finance` namespace.

### C4. Privilege-escalation review

A predecessor left this behind. Do **not** apply it — review it on paper:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer-self-service
  namespace: imaging-dev
rules:
  - apiGroups: ["", "apps"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["create", "update", "bind"]
```

In `README.md`:

1. Identify **three** distinct problems, in order of severity.
2. Explain the specific escalation path the second rule opens — how could a holder of this Role obtain permissions nobody intended to grant?
3. Rewrite it as a least-privilege Role for a developer who needs to deploy and debug their own app in `imaging-dev`. Put the YAML in `partC-rbac/`.

---

## Part D — RBAC troubleshooting

[broken/](broken/) contains three RBAC configurations already deployed at Acme Imaging, each generating a support ticket. Every file's header comment carries the exact error report.

For each of `task-d1.yaml`, `task-d2.yaml`, `task-d3.yaml`:

1. **Reproduce** the reported failure on your cluster (create the namespaces first).
2. **Diagnose** it with the *Safe investigation order* from the troubleshooting reference — capture the `kubectl auth can-i` / `describe` commands that led you to the cause, not just the conclusion.
3. **Fix** it with the smallest change that closes the ticket without over-granting.
4. **Verify** and capture the now-passing command.

Save corrected files in `partD-fixes/` with a short diagnosis each (2–4 sentences: symptom → root cause → fix).

| File | Note |
|---|---|
| `task-d1.yaml` | One defect. |
| `task-d2.yaml` | One defect, plus an extra permission to identify for `describe` to be useful. |
| `task-d3.yaml` | **Two independent defects.** Find both. |

> The diagnostic trail is the real work. Resist fixing by broadening — a wildcard or a dropped `resourceNames` makes the ticket disappear without teaching you anything, and quietly reopens the boundary you spent Part C establishing.

---

## Part E — Write-up

Close `README.md` with a short section (~300–400 words):

- Which single RBAC decision you made would cause the most damage if you got it wrong, and how would you catch that mistake before it reached production?
- You must onboard a third application team next week. Which parts of what you built are reusable as-is, and which must be duplicated per namespace? Why?
- Name one thing you built here that you'd do differently in a real production cluster, and what stopped you this time.

---

## Before you wrap up — self-check

```bash
# 1. Everything you wrote applies cleanly
kubectl apply --dry-run=server -f partA-workloads/ -f partB-config/ -f partC-rbac/

# 2. No wildcards in your RBAC
grep -rn '"\*"' partC-rbac/ partD-fixes/ && echo "^^ FIX THESE"

# 3. No cluster-admin, no stray ClusterRoleBindings
grep -rn 'cluster-admin\|ClusterRoleBinding' partC-rbac/

# 4. No credentials committed
git status --porcelain --ignored | grep -iE '\.key$|\.crt$|kubeconfig|secret\.yaml$'

# 5. Your own RBAC review, as the reference doc recommends
kubectl auth can-i --list -n imaging-dev --as=system:serviceaccount:imaging-dev:ci-deployer
```

## Checklist

- [ ] A1 ReplicaSet — replacement captured, relabelled Pod explained
- [ ] A2 Deployment — rolling update with both ReplicaSets shown, rollback + revision history
- [ ] A3 StatefulSet — creation order, termination order, `redis-0` name reuse
- [ ] A4 DaemonSet — `DESIRED` explained without a replica count
- [ ] A5 Job + CronJob — success, deliberate failure with retries, manual trigger
- [ ] A6 init container blocking, sidecar, `postStart`/`preStop`, readiness probe, shutdown sequence traced
- [ ] B1 ConfigMap — env *and* volume in one spec, reload difference demonstrated
- [ ] B2 Secret — `secretKeyRef`, base64 recovery, two real controls named
- [ ] C1 `ci-deployer` — name-limited, scale works, plural `list` denial explained
- [ ] C2 `dr-patel` — real kubeconfig, four denials captured, revocation explained
- [ ] C3 One ClusterRole + two RoleBindings, future-namespace risk explained
- [ ] C4 Three problems ranked, escalation path traced, least-privilege rewrite
- [ ] D1–D3 reproduced, diagnosed with evidence, minimally fixed, verified
- [ ] E write-up complete
- [ ] `OUTPUT.md` has real output backing every claim in `README.md`
- [ ] No keys, kubeconfigs or tokens committed
