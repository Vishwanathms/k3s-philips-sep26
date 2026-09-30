# Output — ex05 Node & Host Security

Real run against `lab-g2-vm2`, 2026-09-14.

## A real CIS Kubernetes Benchmark run, via kube-bench

```
$ kubectl apply -f kube-bench-job.yaml
job.batch/kube-bench created
$ kubectl get job kube-bench -n day11-security
kube-bench   Complete   1/1   7s
```

Used kube-bench's own `k3s-cis-1.24` profile (not the generic CIS
benchmark) — k3s ships different config file paths/layout than a vanilla
`kubeadm` cluster, so a generic profile false-positives heavily; kube-bench
ships a k3s-specific one that knows the real paths (`/etc/rancher/k3s/`,
`/var/lib/rancher/k3s/`).

```
$ kubectl logs -n day11-security job/kube-bench
[PASS] 4.2.1  --anonymous-auth is set to false
[PASS] 4.2.2  --authorization-mode is not AlwaysAllow
[PASS] 4.2.3  --client-ca-file is set
[PASS] 4.2.4  --read-only-port is set to 0
[PASS] 4.2.11 --rotate-certificates is not false
[PASS] 4.2.12 RotateKubeletServerCertificate is true
[FAIL] 4.2.6  --protect-kernel-defaults is set to true
[FAIL] 4.2.10 --tls-cert-file and --tls-private-key-file are set
[WARN] 4.2.9  eventRecordQPS (manual check)
[WARN] 4.2.13 Strong Cryptographic Ciphers only (manual check)

== Summary node ==
14 checks PASS
2 checks FAIL
2 checks WARN
5 checks INFO
```

**14 real PASS** out of 23 applicable checks, on a cluster nobody has
specifically hardened for this benchmark — k3s's own secure-by-default
choices (anonymous auth off, read-only kubelet port off, cert rotation on)
account for most of them. The **2 real FAILs**, with kube-bench's own
k3s-specific remediation:

```
4.2.6  Add to /etc/rancher/k3s/config.yaml:
         protect-kernel-defaults: true
       then: systemctl restart k3s.service

4.2.10 K3s already auto-generates a kubelet TLS cert/key at
       /var/lib/rancher/k3s/agent/serving-kubelet.{crt,key} - this check
       expects them set EXPLICITLY via kubelet-arg, which k3s doesn't do
       by default (it relies on its own auto-generation instead). Arguably
       a benchmark-vs-k3s-defaults mismatch, not a real gap - but worth
       knowing why it flags.
```

Neither FAIL was applied to the live cluster in this lab — both require the
same `config.yaml` + restart pattern used carefully elsewhere this course
(ex02's real k3s restart risk applies equally here), left as a documented,
actionable finding rather than an unreviewed live change.

## Seccomp: disabled by default on this cluster, confirmed empirically

```
$ kubectl run seccheck-default --image=busybox:1.36 -n day11-security --restart=Never -- sleep 3600
$ kubectl exec seccheck-default -n day11-security -- grep Seccomp /proc/1/status
Seccomp:         0        # 0 = disabled, no syscall filter at all
```

```
$ kubectl apply -f pod-seccomp-runtimedefault.yaml     # explicit seccompProfile.type: RuntimeDefault
$ kubectl exec seccheck-runtimedefault -n day11-security -- grep Seccomp /proc/1/status
Seccomp:         2        # 2 = filtered/enforced
Seccomp_filters: 1
```

Same image, same node — the only difference is one line of YAML. **This
cluster does not apply a seccomp filter unless a Pod explicitly asks for
one** — the `SeccompDefault` feature that makes `RuntimeDefault` automatic
cluster-wide is not enabled here. This is exactly what ex04's `restricted`
Pod Security Standard exists to force: without that admission control,
nothing stops a Pod from quietly running with zero syscall filtering.

## AppArmor: the opposite story — enforced automatically

```
$ sudo aa-status
apparmor module is loaded.
173 profiles are loaded.
73 profiles are in enforce mode.

$ kubectl exec seccheck-default -n day11-security -- cat /proc/1/attr/current
cri-containerd.apparmor.d (enforce)
```

Unlike seccomp, **AppArmor IS applied automatically** — containerd's
`cri-containerd.apparmor.d` profile is in `enforce` mode on every container
this cluster runs, with no Pod-level opt-in required, because the host
itself (Ubuntu 24.04, AppArmor enabled by the OS) provides it. Two
different host-hardening mechanisms, two different real default postures on
the exact same node — confirmed, not assumed.

## Cleanup

```
$ kubectl delete job kube-bench -n day11-security
$ kubectl delete pod seccheck-default seccheck-runtimedefault -n day11-security
```
