# Output — ex07 External Exposure

Real run against `lab-g2-vm2`, 2026-09-14. Purely read-only recon — nothing
changed on the host or cluster.

## The two headline findings

```
$ bash port-audit.sh
== Firewall status ==
Status: inactive
```

**The host firewall (`ufw`) is disabled entirely.** Every port below is
reachable from anywhere on the network that can route to
`192.168.230.103` — nothing at the OS level is filtering any of it.

```
== Ports listening on ALL interfaces ==
0.0.0.0:22      systemd (SSH)
0.0.0.0:111     rpcbind
0.0.0.0:2049    (NFS server, kernel-space nfsd)
0.0.0.0:32975   (unattributed - likely kernel nfsd, no owning PID visible)
0.0.0.0:34651   rpc.mountd
0.0.0.0:37227   rpc.statd
0.0.0.0:44833   rpc.mountd
0.0.0.0:56337   rpc.mountd
*:3389          xrdp (RDP)
*:6443          k3s-server (Kubernetes API)
*:10250         k3s-server (kubelet API)
[::]:*          (IPv6 duplicates of the above)
```

**`*:3389` is a full Remote Desktop Protocol server, wide open, unrelated
to Kubernetes entirely** — the single most concerning line in this whole
audit on a shared lab VM with no firewall in front of it. Not a Kubernetes
finding, but exactly the kind of thing an "External Exposure" review is
supposed to catch: attack surface nobody thought to check because it isn't
in any `kubectl get` output.

## Triage

| Port | What | Should be... |
|---|---|---|
| 22 (SSH) | admin access | expected, but restrict source IPs at the firewall in production |
| 111, 2049, mountd/statd ports | NFS server (Day-06's lab dependency) | fine for a lab; in production, NFS exports should be firewalled to only the node subnet, not the whole network |
| **3389 (RDP)** | remote desktop, nothing to do with k3s | **should not be open to the world** — restrict to a management network or VPN, or disable if unused |
| 6443 (kube-apiserver) | Kubernetes API | intentionally reachable (this is exactly what `--tls-san 192.168.230.103` at install time was for, per Day-00) — but should still be firewalled to admin/CI source IPs, not the open internet |
| 10250 (kubelet API) | per-node kubelet API | should generally be reachable only from the control plane, not the whole network |
| 80/443 (Traefik) | intentional public ingress entrypoint | this is the ONE port actually meant to be open broadly — everything else above should be narrower than this |

## The good news: authentication is real, confirmed empirically

```
$ curl -sk https://192.168.230.103:10250/pods
401 Unauthorized
$ curl -sk https://192.168.230.103:6443/api/v1/secrets
401 Unauthorized   ("Unauthorized")
```

Both the kubelet API and the Kubernetes API reject unauthenticated requests
outright — this matches ex05's kube-bench finding
(`--anonymous-auth=false` PASS): being *network-reachable* is not the same
as being *usable* without credentials. The firewall gap is real and should
be fixed, but it is not, on its own, an open door into the cluster.

```
$ curl -sk http://192.168.230.103:80
404   # Traefik responds - no Ingress currently deployed to route to
```

## Cleanup

None — this lab only read state, nothing was created or changed.
