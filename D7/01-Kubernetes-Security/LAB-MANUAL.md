# Lab manual — Kubernetes Security

## Learning objectives

By the end of this lab, students can audit and tighten RBAC to least
privilege, understand what encryption at rest for Secrets actually protects
(and the real operational gotchas in enabling it on k3s), build a
default-deny NetworkPolicy posture and debug why "allowed" traffic can still
be refused, use Pod Security Admission to reject insecure Pod specs at
admission time, run a real CIS benchmark and interpret its findings, enable
and read real Kubernetes audit logs, and audit a node's actual external
attack surface.

## Before starting

```bash
kubectl apply -f 00-namespace.yaml
export NS=day11-security
```

**Heads up on Lab 2 and Lab 6:** both modify this cluster's core server
config and restart `k3s` for real (~15-20s downtime each time, same risk
class as Day-08's certificate rotation). Lab 2 in particular hit a real k3s
bug during this course's own run — read
[ex02's OUTPUT.md](ex02-secrets-management/OUTPUT.md) before running it live
on any cluster you can't afford a brief, unplanned outage on.

---

## Lab 1 — RBAC Best Practices

```bash
kubectl get clusterrolebindings -o json | jq -r '.items[] | select(.roleRef.name=="cluster-admin") |
  .metadata.name + " -> " + (.subjects // [] | map(.kind+":"+.name) | join(","))'

kubectl apply -f ex01-rbac-best-practices/overprivileged.yaml -f ex01-rbac-best-practices/least-privilege.yaml -n "$NS"
kubectl auth can-i --list --as=system:serviceaccount:$NS:overprivileged-sa -n "$NS"
kubectl auth can-i get secrets --as=system:serviceaccount:$NS:overprivileged-sa -n "$NS"   # yes
kubectl auth can-i get secrets --as=system:serviceaccount:$NS:least-privilege-sa -n "$NS"  # no

kubectl apply -f ex01-rbac-best-practices/pod-no-automount.yaml -n "$NS"
kubectl exec no-token-pod -n "$NS" -- ls /var/run/secrets/kubernetes.io/serviceaccount/   # No such file

kubectl delete -f ex01-rbac-best-practices/ -n "$NS"
```

---

## Lab 2 — Secrets Management

```bash
kubectl apply -f ex02-secrets-management/canary-secret.yaml -n "$NS"
kubectl get secret canary-secret -n "$NS" -o jsonpath='{.data.password}' | base64 -d
sudo grep -c "<your canary value>" /var/lib/rancher/k3s/server/db/state.db*   # found in plaintext

# The full enable/prepare/rotate/reencrypt sequence, and the real bug hit
# doing it, is documented step-by-step in ex02's own OUTPUT.md - read that
# before attempting it live.
```

---

## Lab 3 — Network Security

```bash
kubectl apply -f ex03-network-security/deployment.yaml -n "$NS"
kubectl run netcheck --image=busybox:1.36 -n "$NS" --restart=Never -- sleep 3600

kubectl exec netcheck -n "$NS" -- wget -q -T3 -O- http://web    # works, no policy yet

kubectl apply -f ex03-network-security/deny-all.yaml -n "$NS"
kubectl exec netcheck -n "$NS" -- wget -q -T3 -O- http://web    # "bad address" - DNS itself is blocked

kubectl apply -f ex03-network-security/allow-web-ingress.yaml -n "$NS"
kubectl exec netcheck -n "$NS" -- wget -q -T3 -O- http://web    # still refused! ingress alone isn't enough

kubectl apply -f ex03-network-security/allow-egress-to-web.yaml -n "$NS"
kubectl exec netcheck -n "$NS" -- wget -q -T3 -O- http://web    # now works - both sides authorized
kubectl exec netcheck -n "$NS" -- nc -w3 db 5432                 # db: still fully blocked

kubectl delete -f ex03-network-security/ -n "$NS"
kubectl delete pod netcheck -n "$NS"
```

---

## Lab 4 — Container Image Security

```bash
kubectl label namespace "$NS" pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=latest

kubectl apply -f ex04-container-image-security/pod-privileged.yaml -n "$NS"       # Forbidden
kubectl apply -f ex04-container-image-security/pod-root-no-context.yaml -n "$NS"  # Forbidden
kubectl apply -f ex04-container-image-security/pod-hardened.yaml -n "$NS"         # Running

sudo k3s ctr run --rm --net-host docker.io/aquasec/trivy:latest scan \
  trivy image --severity HIGH,CRITICAL --quiet nginx:1.27-alpine

kubectl delete pod hardened-pod -n "$NS"
kubectl label namespace "$NS" pod-security.kubernetes.io/enforce- pod-security.kubernetes.io/enforce-version-
```

---

## Lab 5 — Node & Host Security

```bash
kubectl apply -f ex05-node-host-security/kube-bench-job.yaml -n "$NS"
kubectl logs -n "$NS" job/kube-bench

kubectl run seccheck-default --image=busybox:1.36 -n "$NS" --restart=Never -- sleep 3600
kubectl exec seccheck-default -n "$NS" -- grep Seccomp /proc/1/status    # 0 = disabled

kubectl apply -f ex05-node-host-security/pod-seccomp-runtimedefault.yaml -n "$NS"
kubectl exec seccheck-runtimedefault -n "$NS" -- grep Seccomp /proc/1/status   # 2 = enforced

sudo aa-status
kubectl exec seccheck-default -n "$NS" -- cat /proc/1/attr/current       # AppArmor enforce, on by default

kubectl delete job kube-bench -n "$NS"
kubectl delete pod seccheck-default seccheck-runtimedefault -n "$NS"
```

---

## Lab 6 — Log Auditing

```bash
sudo mkdir -p /etc/rancher/k3s
sudo cp ex06-log-auditing/audit-policy.yaml /etc/rancher/k3s/audit-policy.yaml
python3 -c "import yaml; yaml.safe_load(open('ex06-log-auditing/audit-policy.yaml'))"   # validate first

# write /etc/rancher/k3s/config.yaml with the kube-apiserver-arg audit flags
# (see ex06's OUTPUT.md for the exact content), then:
sudo tar czf /tmp/k3s-pre-audit-backup.tar.gz -C /var/lib/rancher/k3s/server .   # safety backup
sudo systemctl restart k3s
kubectl get node   # wait for Ready

kubectl create secret generic audit-test-secret -n "$NS" --from-literal=key=auditvalue
sudo grep -m1 "audit-test-secret" /var/log/k3s-audit.log | python3 -m json.tool

# revert:
sudo rm /etc/rancher/k3s/config.yaml /etc/rancher/k3s/audit-policy.yaml
sudo systemctl restart k3s
kubectl delete secret audit-test-secret -n "$NS"
```

---

## Lab 7 — External Exposure

```bash
bash ex07-external-exposure/port-audit.sh
```

Purely read-only — no cleanup needed.

---

## Troubleshooting sequence

```bash
kubectl auth can-i --list --as=<user-or-sa> -n <ns>          # what CAN this identity actually do
kubectl describe pod <name> -n <ns> | tail -10                # PodSecurity/scheduling rejections show here
kubectl describe networkpolicy -n <ns>                        # which rules apply to which Pods
sudo journalctl -u k3s --no-pager | tail -50                  # k3s server config/restart issues
sudo k3s secrets-encrypt status
sudo ss -tlnp | grep -v 127.0.0.1                              # what's actually externally reachable
```

| Symptom | Likely cause |
|---|---|
| A Pod that should work is Forbidden at creation | Pod Security Admission (`restricted`/`baseline`) on the namespace - check `kubectl get ns <ns> -o yaml \| grep pod-security` |
| NetworkPolicy "allow" rule doesn't seem to work | check BOTH sides - the source's egress AND the target's ingress must independently permit it |
| `k3s secrets-encrypt` subcommands fail with "missing annotation" | a real, reproducible bug this course hit - see [ex02's OUTPUT.md](ex02-secrets-management/OUTPUT.md) for full diagnosis and recovery |
| `k3s ctr` / `ctr` says image not found even though `crictl images` shows it | you're talking to the wrong containerd - use `sudo k3s ctr`, not plain `ctr`, for k3s-pulled images |
| kube-bench checks show `[INFO]` instead of PASS/FAIL | that check needs the `--benchmark` value to match this k3s version's profile, or needs config it can't auto-detect from mounted paths alone |

## Cleanup

```bash
kubectl delete namespace day11-security
sudo k3s secrets-encrypt status                    # confirm: Disabled, no configuration file found
sudo test -f /etc/rancher/k3s/config.yaml && echo "STILL PRESENT - remove it" || echo "clean"
```
