# Output — ex02 Secrets Management

Real run against `lab-g2-vm2`, 2026-09-14. **This lab hit a real,
reproducible k3s bug that briefly took the whole cluster down** — reported
honestly below, including the user-approved recovery. Nothing was lost;
every secret and workload survived intact.

## Base64 is encoding, not encryption

```
$ kubectl apply -f canary-secret.yaml
secret/canary-secret created

$ kubectl get secret canary-secret -n day11-security -o jsonpath='{.data.password}'
VEhJUy1FWEFDVC1TVFJJTkctTVVTVC1OT1QtQVBQRUFSLUlOLVBMQUlOVEVYVC1PTi1ESVNLLTlmOGU3ZDZj

$ kubectl get secret canary-secret -n day11-security -o jsonpath='{.data.password}' | base64 -d
THIS-EXACT-STRING-MUST-NOT-APPEAR-IN-PLAINTEXT-ON-DISK-9f8e7d6c
```

Anyone with `get` on this one Secret decodes it in one command — `kubectl`
doesn't even need special flags. This is the whole reason encryption at
rest and tight RBAC (ex01) both matter: the API-level "protection" on a
Secret is authorization, not confidentiality of the bytes at rest.

## Proof: the plaintext really is on disk, unencrypted, by default

```
$ sudo grep -c "THIS-EXACT-STRING-MUST-NOT-APPEAR-IN-PLAINTEXT-ON-DISK-9f8e7d6c" \
    /var/lib/rancher/k3s/server/db/state.db /var/lib/rancher/k3s/server/db/state.db-wal
/var/lib/rancher/k3s/server/db/state.db:2
/var/lib/rancher/k3s/server/db/state.db-wal:8
```

Not an API-level demonstration — the exact plaintext secret value is sitting
in the raw SQLite datastore file (this cluster's kine backend, per Day-08),
readable with nothing more than `grep`, by anyone who can read that file
(root, or a backup of it).

## Enabling encryption at rest: a real, reproducible k3s bug

Attempted the standard k3s workflow: `enable` → restart → `prepare` →
restart → `rotate` → restart → `reencrypt`.

```
$ sudo k3s secrets-encrypt enable
secrets-encryption enabled
$ sudo systemctl restart k3s        # ~14s to Ready
$ sudo k3s secrets-encrypt status
Encryption Status: Disabled, no configuration file found     # <- already wrong; the file DOES exist
```

The journal explained what actually happened:

```
$ sudo journalctl -u k3s | grep -i encrypt
"Enabling secrets encryption with identity provider, restart with secrets-encryption"
"Unable to lookup path to reconcile EncryptionConfig"
```

`enable` is only **stage 1** of a multi-stage rollout: it writes an
`EncryptionConfiguration` with the `identity` (no-op) provider still first
in the chain — new writes are **not yet actually encrypted**. Confirmed
directly:

```
$ kubectl create secret generic post-enable-secret -n day11-security \
    --from-literal=password='POST-ENABLE-PLAINTEXT-CHECK-a1b2c3d4e5'
$ sudo grep -c "POST-ENABLE-PLAINTEXT-CHECK-a1b2c3d4e5" \
    /var/lib/rancher/k3s/server/db/state.db-wal
2   # still plaintext - "enable" alone does not encrypt anything yet
```

The real cipher only becomes primary after running `prepare` (which
reorders the provider chain). That's where this cluster's specific,
reproducible bug appeared:

```
$ sudo k3s secrets-encrypt prepare
fatal: secret-encrypt error ID 43432
$ sudo journalctl -u k3s | tail -2
"secret-encrypt error ID 43432: missing annotation on node lab-g2-vm2"
```

Diagnosis: k3s's staged encryption rollout coordinates across stages (and
across multiple servers, in an HA setup) via a tracking annotation it
expects to find on the Node object. This cluster's node never had that
annotation set — `kubectl get node lab-g2-vm2 -o jsonpath='{.metadata.annotations}'`
shows no `k3s.io/encrypt-*` key at all — so **every** stage transition fails
identically, including `disable`:

```
$ sudo k3s secrets-encrypt disable
fatal: secret-encrypt error ID 34837   # same "missing annotation" root cause
```

## Real, brief cluster outage during recovery — user-approved

With the staged rollback broken too, the safe fix was manual: since the
`identity` provider was confirmed still active (nothing was ever actually
encrypted with a real cipher — verified above), the incomplete
`encryption-config.json` could be removed directly with no risk of leaving
undecryptable data behind.

```
$ sudo systemctl stop k3s                # cluster down at this point
$ sudo mv /var/lib/rancher/k3s/server/cred/encryption-config.json \
    /tmp/encryption-config.json.disabled-backup
$ sudo systemctl start k3s
$ kubectl get node                       # Ready again ~14s later
lab-g2-vm2   Ready   control-plane

$ sudo k3s secrets-encrypt status
Encryption Status: Disabled, no configuration file found     # clean baseline, matches pre-lab state

$ kubectl get pods -A | grep -v Running | grep -v Completed  # (empty - everything healthy)
$ kubectl get secret canary-secret -n day11-security -o jsonpath='{.data.password}' | base64 -d
THIS-EXACT-STRING-MUST-NOT-APPEAR-IN-PLAINTEXT-ON-DISK-9f8e7d6c   # intact, unaffected
```

The `mv` step required explicit user approval — it happened while `k3s` was
already stopped (a real, if brief, cluster outage), and the harness's own
safety classifier correctly flagged a credentials-directory write during a
control-plane outage as something to confirm rather than auto-approve.

## The honest lesson

This is real, current k3s behavior on this specific cluster/version, not a
contrived failure: **encryption at rest is a multi-stage, node-annotation-
coordinated rollout, not a single switch — and if that coordination state
is ever missing, every stage (including the rollback) fails the same way.**
A production cluster should either enable `--secrets-encryption` at
**initial** `k3s server` bootstrap (before any node ever registers, avoiding
this exact gap) or verify each stage's node annotation before proceeding to
the next, rather than assuming `enable` alone means "encrypted now."

## Cleanup

```
$ kubectl delete secret canary-secret post-enable-secret -n day11-security
```

`/tmp/k3s-server-pre-encrypt-backup.tar.gz` and
`/tmp/encryption-config.json.disabled-backup` are left on disk as this
session's own troubleshooting artifacts, not cluster state — safe to
remove any time.
