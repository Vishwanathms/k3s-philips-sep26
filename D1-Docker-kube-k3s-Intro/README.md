# D1 — Docker, Kubernetes & k3s introduction

Install k3s, confirm it works, and run the first two workloads. Everything
here runs in one namespace, **`d1-intro`**.

## Install and validate first

Work through these in order before the exercises — they set up the cluster
the rest of the course uses.

| Manual | Purpose |
|---|---|
| [LM-02-INSTALL-ubuntu-24.04.md](LM-02-INSTALL-ubuntu-24.04.md) | Install a single-node k3s cluster on Ubuntu 24.04 |
| [LM-01-Basic-check-commands.md](LM-01-Basic-check-commands.md) | Validate the install: node Ready, system Pods, kubeconfig |
| [LM-03-Basic-pod-creation.md](LM-03-Basic-pod-creation.md) | First Pod, imperative vs declarative |
| [LM-04-Restart-check.md](LM-04-Restart-check.md) | What survives a reboot, and what k3s restarts for you |

## Hands-on labs

| # | Lab | Proves | Verified run |
|---|-----|--------|--------------|
| 1 | [ex01-nginx](ex01-nginx/) | a `Deployment` keeps 2 replicas alive; a `NodePort` `Service` reaches them from outside the cluster | [OUTPUT.md](ex01-nginx/OUTPUT.md) |
| 2 | [ex02-python-redis](ex02-python-redis/) | two workloads find each other by `Service` **name** alone — the app's `REDIS_HOST` default is `redis`, so no wiring is needed | [OUTPUT.md](ex02-python-redis/OUTPUT.md) |

Each exercise has its own `README.md` (apply + verify) and `LAB-MANUAL.md`
(the teaching walk-through).

## Namespace

Every manifest in D1 is pinned to `d1-intro`. Create it once and make it your
default, so the commands in each exercise need no `-n`:

```bash
kubectl apply -f 00-namespace.yaml
kubectl config set-context --current --namespace=d1-intro
```

Cleanup, and putting your context back:

```bash
kubectl delete namespace d1-intro
kubectl config set-context --current --namespace=default
```

## Prerequisites

```bash
kubectl get nodes        # Ready
kubectl get pods -A      # coredns, traefik, metrics-server, local-path all Running
```

## Reference material

| File | What |
|---|---|
| [1.Kubernetes_Fundamentals.pdf](1.Kubernetes_Fundamentals.pdf) | Slide deck: core objects and the control plane |
| [2.Kubernetes_YAML.pdf](2.Kubernetes_YAML.pdf) | Slide deck: reading and writing manifests |
| [3.k3s-examples-explanined.pdf](3.k3s-examples-explanined.pdf) | Slide deck: these examples, annotated |
| `I1`–`I4` `.png` | Architecture and traffic-flow diagrams used in the slides |

## What comes next

D2 takes the same python + redis app and makes its configuration explicit —
environment variables, ConfigMaps, Secrets — then adds RBAC.
