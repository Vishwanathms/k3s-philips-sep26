# Output — ex06 Log Auditing

Real run against `lab-g2-vm2`, 2026-09-14. Learning from ex02's close call,
this change was made carefully: policy YAML validated before use, a fresh
`/var/lib/rancher/k3s/server` backup taken first, restart done with a
bounded wait, and reverted to baseline at the end — see the full sequence
below.

## Enabling k3s audit logging — the supported way, via `config.yaml`

Unlike ex02's `secrets-encrypt` (a staged, node-annotation-coordinated
subcommand), audit logging is just two apiserver flags — no multi-stage
rollout, no cross-restart coordination state to get out of sync.

```
$ sudo mkdir -p /etc/rancher/k3s
$ sudo cp audit-policy.yaml /etc/rancher/k3s/audit-policy.yaml
$ python3 -c "import yaml; yaml.safe_load(open('audit-policy.yaml'))"   # validated first
```

```
$ sudo tee /etc/rancher/k3s/config.yaml
kube-apiserver-arg:
  - "audit-log-path=/var/log/k3s-audit.log"
  - "audit-policy-file=/etc/rancher/k3s/audit-policy.yaml"
  - "audit-log-maxage=2"
  - "audit-log-maxbackup=2"
  - "audit-log-maxsize=50"
```

```
$ sudo tar czf /tmp/k3s-server-pre-audit-backup.tar.gz -C /var/lib/rancher/k3s/server .   # fresh safety backup first

12:34:28  $ sudo systemctl restart k3s
12:34:46  $ kubectl get node
lab-g2-vm2   Ready   control-plane        # ~18s to Ready, no repeat of ex02's issue

$ kubectl get pods -A | grep -v Running | grep -v Completed
(empty - every Pod cluster-wide healthy)

$ sudo ls -la /var/log/k3s-audit.log
-rw------- 1 root root 3905960 ... /var/log/k3s-audit.log   # writing immediately
```

## The policy: narrow on purpose

See [audit-policy.yaml](audit-policy.yaml) — `RequestResponse` (full
request+response bodies) only for **Secrets** and **exec/attach**, the two
highest-value/highest-risk targets; `Metadata` (who/what/when, no bodies)
for everything else; system-component health-check noise skipped entirely.
A real production policy would go further, but this is deliberately small
so the log stays legible for the lab.

## Real events, actually captured

```
$ kubectl create secret generic audit-test-secret -n day11-security --from-literal=key=auditvalue
$ sudo grep -m1 "audit-test-secret" /var/log/k3s-audit.log | python3 -m json.tool | head -8
{
  "stage": "ResponseComplete",
  "verb": "create",
  "user": {"username": "system:admin"},
  "objectRef": {"resource": "secrets", "namespace": "day11-security",
                 "name": "audit-test-secret", "apiVersion": "v1"},
  "responseStatus": {"code": 201}
}
```

The `RequestResponse` level really did capture the full request AND
response object for this Secret (`requestObject`/`responseObject` both
present in the raw event) — exactly who created it, when, and what it
contained.

```
$ kubectl exec audit-exec-test -n day11-security -- echo "hello from audit test"
$ sudo grep -m1 '"subresource":"exec"' /var/log/k3s-audit.log | python3 -m json.tool
{
  "verb": "get",
  "user": {"username": "system:admin"},
  "objectRef": {"resource": "pods", "namespace": "day11-security",
                 "name": "audit-exec-test", "subresource": "exec"},
  "requestURI": "/api/v1/namespaces/day11-security/pods/audit-exec-test/exec?
                 command=echo&command=hello+from+audit+test&container=audit-exec-test..."
}
```

The **exact command run inside the container is in the audit log's
`requestURI`** — `exec` isn't just logged as "someone execced into a pod",
the specific command arguments are captured too. This is the concrete
answer to "who ran what, inside which container, and when" that a real
incident investigation needs.

## Reverted to baseline

Audit logging is left **disabled** at the end of this lab, matching this
course's standing practice of leaving the cluster exactly as it started
after each lab (distinct from Day-06/09's precedent of leaving a genuinely
new *capability* like NFS/VPA installed for future days — audit logging
changes ongoing apiserver behavior and disk usage indefinitely, so it's
reverted here rather than left on unannounced):

```
$ sudo rm /etc/rancher/k3s/config.yaml /etc/rancher/k3s/audit-policy.yaml
$ sudo systemctl restart k3s
$ kubectl get node                        # Ready again, ~15s
$ sudo test -f /var/log/k3s-audit.log && echo still-there
still-there   # old log kept on disk (harmless, 3.9MB) - not actively written to anymore
```

In a real production cluster, this is exactly the config you'd want to
**keep enabled permanently** — the trade-off here is purely "don't
silently change this shared lab cluster's long-term behavior without it
being asked for."

## Cleanup

```
$ kubectl delete secret audit-test-secret -n day11-security
$ kubectl delete pod audit-exec-test -n day11-security
```
