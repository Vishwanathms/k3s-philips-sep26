# Day 11 — Kubernetes Security

Builds directly on:

- **Day 01–10:** RBAC (Day 02) and NetworkPolicy (Day 04/05/09) already
  introduced the mechanisms; this day is about using them as a deliberate
  security posture, auditing what's already misconfigured on this real
  cluster, and the layers below Kubernetes itself (the node, the host, the
  network).

This module covers the full breadth of the topic list — Security
Guidelines, Network Security, RBAC Best Practices, Secrets Management,
Container Image Security, Node Security, Host Security, Log Auditing,
External Exposure — as seven hands-on labs, all run for real against this
cluster, plus a synthesized best-practices checklist (the "Security
Guidelines" throughline) in the slides.

| Material | Purpose |
|---|---|
| [slides/PPT_CONTENT.md](slides/PPT_CONTENT.md) | Detailed slide-by-slide teaching content, presenter cues, and sources |
| [slides/Day-11-Kubernetes-Security.pptx](slides/Day-11-Kubernetes-Security.pptx) | Presentation-ready PowerPoint deck |

## Hands-on labs

| # | Lab | Proves | Verified run |
|---|-----|--------|--------------|
| 1 | [ex01-rbac-best-practices](ex01-rbac-best-practices/) | a wildcard Role can read every Secret in a namespace; least-privilege can't; `automountServiceAccountToken: false` removes a whole attack surface | [OUTPUT.md](ex01-rbac-best-practices/OUTPUT.md) |
| 2 | [ex02-secrets-management](ex02-secrets-management/) | Secret plaintext really is on disk unencrypted by default; hit and safely recovered from a real, reproducible k3s encryption-at-rest bug | [OUTPUT.md](ex02-secrets-management/OUTPUT.md) |
| 3 | [ex03-network-security](ex03-network-security/) | default-deny-all NetworkPolicy, and the real, subtle finding that BOTH the caller's egress and the target's ingress must independently allow a connection | [OUTPUT.md](ex03-network-security/OUTPUT.md) |
| 4 | [ex04-container-image-security](ex04-container-image-security/) | Pod Security Admission's `restricted` profile really rejects privileged/root Pods at admission; a real Trivy scan found 36 real HIGH/CRITICAL CVEs in this course's own nginx image | [OUTPUT.md](ex04-container-image-security/OUTPUT.md) |
| 5 | [ex05-node-host-security](ex05-node-host-security/) | a real CIS Kubernetes Benchmark run (kube-bench, k3s-specific profile) — 14 real PASS, 2 real FAIL with remediation; seccomp is OFF by default here, AppArmor is ON by default | [OUTPUT.md](ex05-node-host-security/OUTPUT.md) |
| 6 | [ex06-log-auditing](ex06-log-auditing/) | real k3s audit logging enabled, capturing the exact `exec` command run inside a container and full Secret request/response bodies — then safely reverted | [OUTPUT.md](ex06-log-auditing/OUTPUT.md) |
| 7 | [ex07-external-exposure](ex07-external-exposure/) | this host's firewall is disabled; a full RDP server and the Kubernetes/kubelet APIs are reachable from the whole network — though both APIs do reject unauthenticated requests | [OUTPUT.md](ex07-external-exposure/OUTPUT.md) |

Start with [LAB-MANUAL.md](LAB-MANUAL.md). All seven hands-on labs were run
for real against this cluster on **2026-09-14** — every lab's own
`OUTPUT.md` has the full captured transcript.

```bash
kubectl delete namespace day11-security   # fast cleanup for lab objects
```

## What this day needed that earlier days didn't

**Two labs modified this cluster's core server configuration and
restarted `k3s` for real** (ex02, ex06) — the same risk category as Day-08's
certificate rotation, but this time one of them (ex02) hit a **real,
reproducible k3s bug**: the staged secrets-encryption rollout
(`enable`→`prepare`→`rotate`→`reencrypt`) failed at every stage with
`missing annotation on node`, including the built-in `disable` rollback.
Recovering required stopping `k3s`, manually removing the incomplete
encryption config, and restarting — a real, brief, **user-approved**
outage (the harness's own safety classifier correctly paused for explicit
approval before touching a credentials-directory file while the control
plane was down). Full details, including the exact commands and log lines,
are in [ex02's OUTPUT.md](ex02-secrets-management/OUTPUT.md). Nothing was
lost; the cluster was fully healthy and back to its exact pre-lab baseline
within seconds each time.

**ex06's audit logging was deliberately reverted at the end of the lab** —
unlike Day-06's NFS/CSI or Day-09's VPA (durable capabilities left running
for future days), ongoing audit logging changes apiserver behavior and disk
usage indefinitely, so this course's standing "leave the cluster as found"
practice applies here rather than the "leave it installed" one.

**ex05 used `sudo k3s ctr`, not plain `ctr`** — this host runs a system
containerd alongside k3s's own embedded one (a known quirk from Day-00's
install), and the two have completely separate image stores.

## Capstone stage 09

After the labs above, students lock down the course capstone: install
`linkerd-cni` so Pod Security Admission can be enforced at `restricted`,
give each tier its own ServiceAccount (no token automount), run every
container non-root with a read-only root filesystem, put the redis
password in a Secret, and add default-deny NetworkPolicies for the exact
web→api→redis path. An intruder drill and a Trivy scan close it out.
Manual: [CAPSTONE/Stage09-Security/LAB-MANUAL.md](../CAPSTONE/Stage09-Security/LAB-MANUAL.md).

## Prerequisites

```bash
kubectl get node -o wide
sudo k3s secrets-encrypt status     # confirms baseline: Disabled
sudo aa-status --enabled            # AppArmor available on this host
```
