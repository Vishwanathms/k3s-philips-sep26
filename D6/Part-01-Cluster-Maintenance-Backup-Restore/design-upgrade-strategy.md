# Design exercise — k3s upgrade strategy

**Deliberately not executed on this cluster.** Every prior day's captured
`OUTPUT.md` cites `k3s v1.36.4+k3s1` as the baseline; changing that version
for real would be a lasting, one-way change (k3s does not support
downgrading a server back down) affecting every other day sharing this one
node — the same reasoning Day 04 used to keep its CNI-migration content
design-only rather than live. This is real procedure, real commands,
rehearsed and explained — just not run here.

## What's actually true about this cluster right now

```console
$ k3s --version
k3s version v1.36.4+k3s1 (4dedb15b)

$ curl -s https://api.github.com/repos/k3s-io/k3s/releases/latest \
    | grep tag_name
"tag_name": "v1.36.4+k3s1"
```

Checked live: this cluster is already on the current latest stable release
— there is nothing newer to upgrade *to* today. The procedure below is what
you'd run when that stops being true.

## The single-node reality check

The textbook safe-upgrade sequence is **cordon → drain → upgrade →
uncordon**, one node at a time, so traffic shifts to other nodes while each
one is worked on. On this cluster:

- `cordon`/`drain` (Labs 1–2) still apply — cordoning stops new work
  landing mid-upgrade — but `drain` has nowhere to send the evicted Pods.
- The realistic sequence here is **cordon → upgrade → uncordon**, accepting
  a real, short API/workload restart (the same few seconds `ex03`'s
  certificate rotation and `ex04`/`ex05`'s backup/restore measured) instead
  of the zero-downtime multi-node version.

## The actual upgrade command

k3s upgrades by re-running the install script with a pinned version — it
replaces the binary and restarts the service itself:

```bash
kubectl cordon lab-g2-vm2                    # stop new Pods landing mid-upgrade

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION=v1.37.0+k3s1 \
  sh -s - server --write-kubeconfig-mode 0644 --tls-san 192.168.230.103
# (repeat the same flags this cluster was originally installed with -
#  see Day-00's INSTALL-ubuntu-24.04.md)

kubectl get nodes                            # confirm the new VERSION column
kubectl get pods -A                          # confirm every workload recovered
kubectl uncordon lab-g2-vm2
```

Rancher also ships the **system-upgrade-controller** for automating this
across many nodes on a schedule (a Kubernetes-native operator that watches
for a `Plan` CRD and drains/upgrades/uncordons nodes itself) — appropriate
once there's more than one node to coordinate; overkill for one.

## Rollback: the part that's genuinely different from backup/restore

`ex04`/`ex05` proved the **datastore** restores cleanly and fast. Version
rollback is not the same operation:

- k3s **does not officially support downgrading** a server node's version —
  the datastore schema/data format can move forward across releases in
  ways that aren't guaranteed reversible.
- The supported rollback path if an upgrade goes wrong is **ex05's restore**
  — a datastore backup taken *before* the upgrade, restored onto the *old*
  binary (re-run the install script pinned to the previous
  `INSTALL_K3S_VERSION` first, then restore).

## Pre-upgrade checklist

- [ ] Read the release notes between the current and target version for
      breaking changes (deprecated APIs, changed defaults, CRD version
      bumps for anything installed — the NFS CSI driver from Day 06,
      Traefik's config from Day 05).
- [ ] Take a datastore backup **immediately before** starting (`ex04`) —
      this is the actual rollback path, not the version itself.
- [ ] Know the exact previous `INSTALL_K3S_VERSION` string to re-pin if
      you need to reinstall the old binary before restoring.
- [ ] Cordon before touching anything (`ex01`).
- [ ] After upgrading: `kubectl get nodes` for the version string,
      `kubectl get pods -A` for everything Running, then uncordon.
- [ ] On a multi-node cluster: one node at a time, `drain` for real between
      each (`ex02`), never all nodes simultaneously.
