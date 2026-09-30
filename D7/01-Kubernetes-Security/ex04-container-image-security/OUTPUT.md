# Output — ex04 Container Image Security

Real run against `lab-g2-vm2`, 2026-09-14.

## Part 1 — Pod Security Admission, `restricted` profile

Built into every Kubernetes cluster since v1.25 (no install needed, unlike
Day-09's VPA) — a namespace label is all it takes:

```
$ kubectl label namespace day11-security \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/enforce-version=latest
namespace/day11-security labeled
```

### Rejected: privileged + root + no hardening at all

```
$ kubectl apply -f pod-privileged.yaml
Error from server (Forbidden): pods "privileged-pod" is forbidden:
violates PodSecurity "restricted:latest":
  privileged (container "app" must not set securityContext.privileged=true),
  allowPrivilegeEscalation != false (container "app" must set securityContext.allowPrivilegeEscalation=false),
  unrestricted capabilities (container "app" must set securityContext.capabilities.drop=["ALL"]),
  runAsNonRoot != true (pod or container "app" must set securityContext.runAsNonRoot=true),
  seccompProfile (pod or container "app" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```

Every violation is named individually — this is an actionable checklist,
not just a yes/no rejection.

### Rejected: not privileged, but still no hardening

```
$ kubectl apply -f pod-root-no-context.yaml
Error from server (Forbidden): pods "root-no-context-pod" is forbidden:
violates PodSecurity "restricted:latest":
  allowPrivilegeEscalation != false, unrestricted capabilities,
  runAsNonRoot != true, seccompProfile ...
```

`restricted` requires everything to be **explicit** — omitting a
`securityContext` entirely is treated exactly like requesting the unsafe
defaults, not like asking for something safe.

### Accepted: every requirement met explicitly

```
$ kubectl apply -f pod-hardened.yaml
pod/hardened-pod created
$ kubectl get pod hardened-pod -n day11-security
hardened-pod   1/1   Running   0   11s
```

`runAsNonRoot: true` + `runAsUser: 1000`, `seccompProfile.type:
RuntimeDefault`, `allowPrivilegeEscalation: false`,
`capabilities.drop: ["ALL"]`, `readOnlyRootFilesystem: true` — the same
`busybox:1.36` image as the two rejected Pods, just declared safely.

## Part 2 — a real Trivy vulnerability scan

```
$ sudo k3s ctr run --rm --net-host docker.io/aquasec/trivy:latest scan \
    trivy image --severity HIGH,CRITICAL --quiet nginx:1.27-alpine

Target: nginx:1.27-alpine (alpine 3.21.3)
Total: 36 (HIGH: 34, CRITICAL: 2)
```

36 real, currently-tracked HIGH/CRITICAL CVEs (openssl, libxml2, musl,
nghttp2, zlib — each with a live `avd.aquasec.com` reference) in the exact
`nginx:1.27-alpine` image ex03's `web` Deployment ran, unpatched at the OS
package level, from a genuinely current vulnerability database — this is
what image scanning in a CI pipeline (`trivy image --exit-code 1 ...` to
fail a build) is protecting against.

```
$ sudo k3s ctr run --rm --net-host docker.io/aquasec/trivy:latest scan2 \
    trivy image --severity HIGH,CRITICAL --quiet busybox:1.36
Target: -   Vulnerabilities: -   (not scanned)
```

`busybox:1.36` has no package manager (no `apk`/`apt`) for Trivy to
enumerate against at all — not "0 vulnerabilities found", but "nothing to
scan." A genuinely smaller image (no package database, no shell utilities
beyond busybox's own applet) structurally has less for a scanner (or an
attacker who gets a shell) to work with — one real, concrete reason
"distroless"/minimal base images are a hardening technique in their own
right, independent of scan results.

## Note: `k3s ctr`, not `ctr`

`sudo ctr` alone talks to the **system** containerd on this host (a
separate daemon from k3s's own, per this course's standing note that Docker
+ a system containerd coexist with k3s); the images this course has pulled
all season live in **k3s's own** embedded containerd
(`/run/k3s/containerd/containerd.sock`), reached via `sudo k3s ctr`, not
plain `ctr`. Using the wrong one produces a real, confusing "image not
found" even though `crictl images` (which does talk to k3s's containerd)
shows it right there.

## Cleanup

```
$ kubectl delete pod hardened-pod -n day11-security
$ kubectl label namespace day11-security pod-security.kubernetes.io/enforce- pod-security.kubernetes.io/enforce-version-
```

`privileged-pod` and `root-no-context-pod` never actually existed — the API
server rejected them at admission before they were ever persisted, so
there's nothing to delete for those two.
