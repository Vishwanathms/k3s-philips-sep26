# D3 — Services, networking & ingress

Takes the same python + redis app and makes the **network** explicit: how
Pods find each other, how traffic gets in from outside, and how to stop
traffic that shouldn't flow. Everything here runs in one namespace,
**`d3-networking`**.

## Hands-on labs

| # | Lab | Proves | Verified run |
|---|-----|--------|--------------|
| 1 | [ex01-python-redis-services](ex01-python-redis-services/) | `ClusterIP` vs `LoadBalancer` vs `ExternalName`, and a `NetworkPolicy` that lets only the app reach redis | — |
| 2 | [ex02-traefik-dashboard](ex02-traefik-dashboard/) | read k3s's bundled Traefik from the inside: routers, services and live endpoints per Ingress | [OUTPUT.md](ex02-traefik-dashboard/OUTPUT.md) |
| 3 | [ex03-nginx-dashboard-demo](ex03-nginx-dashboard-demo/) | a second workload behind the same Ingress, watched through the dashboard | [OUTPUT.md](ex03-nginx-dashboard-demo/OUTPUT.md) |

Start with [ex01's LAB-MANUAL.md](ex01-python-redis-services/LAB-MANUAL.md).

## Namespace

Every manifest in D3 is pinned to `d3-networking`, created once at the day
level:

```bash
kubectl apply -f 00-namespace.yaml
```

The exercises pass `-n d3-networking` explicitly, so you do not need to change
your context. Cleanup:

```bash
kubectl delete namespace d3-networking
```

ex02 also reads Traefik itself, which lives in `kube-system` — that namespace
is k3s's own and is never deleted by these labs.

## Reference code

[Ref-codes/](Ref-codes/) holds smaller, single-purpose versions of the same
mechanisms, each with its own captured run — useful when one concept from ex01
needs isolating:

| Folder | Isolates |
|---|---|
| [ex03-loadbalancer](Ref-codes/ex03-loadbalancer/) | `LoadBalancer` on k3s (ServiceLB / klipper) |
| [ex04-externalname](Ref-codes/ex04-externalname/) | `ExternalName` as a DNS-level alias |
| [ex05-headless](Ref-codes/ex05-headless/) | headless Service: DNS returns Pod IPs, not a VIP |
| [ex06-networkpolicy](Ref-codes/ex06-networkpolicy/) | default-deny ingress, then one allow rule |

## Prerequisites

```bash
kubectl get nodes                  # Ready
kubectl get ingressclass           # traefik
kubectl -n kube-system get pods -l app.kubernetes.io/name=traefik   # Running
```

ex01's NetworkPolicy labs need a CNI that enforces policy. k3s's default
Flannel does **not** — the `NetworkPolicy` objects apply cleanly but nothing
is blocked. The lab manual says where this matters.

## Reference material

| File | What |
|---|---|
| [PPT01-Services-Networking-Fundamentals.pdf](PPT01-Services-Networking-Fundamentals.pdf) | Service types, DNS, endpoints |
| [PPT02-K3s-Networking-Deep-Dive.pdf](PPT02-K3s-Networking-Deep-Dive.pdf) | What k3s does differently |
| [PPT03-Flannel_Encryption_VXLAN_vs_WireGuard.pdf](PPT03-Flannel_Encryption_VXLAN_vs_WireGuard.pdf) | Encrypting pod-to-pod traffic |
| [PPT04-CNI_Comparison_Flannel_Canal_Calico_Cilium.pdf](PPT04-CNI_Comparison_Flannel_Canal_Calico_Cilium.pdf) | Choosing a CNI, and which enforce NetworkPolicy |
| [PPT05-NetworkPolicy_Protocols.pdf](PPT05-NetworkPolicy_Protocols.pdf) | NetworkPolicy semantics |
| [PPT-06-Ingress-Traffic-Management.pdf](PPT-06-Ingress-Traffic-Management.pdf) | Ingress, routers and TLS |
| [i1.Reverse-forward-proxy.png](i1.Reverse-forward-proxy.png) | Diagram: forward vs reverse proxy |

## What comes next

D4 gives the app persistent storage; D5 makes it declare its health and its
resource budget.
