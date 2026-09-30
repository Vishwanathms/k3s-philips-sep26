# Capstone stage 09 — Lock it down (Day 11)

## Scenario

The app works, scales and survives failures. Now a security review looks
at it and finds:
- every Pod runs as the namespace's `default` ServiceAccount, with an API
  token mounted it never uses
- nothing stops a Pod from running as root, and every container can write
  anywhere on its own filesystem
- any Pod can talk to any other: the web tier could open redis directly
- redis has no password
- nobody knows what vulnerabilities ship inside the three images

In this stage you fix each one, keep the hit counter working throughout,
and then play the attacker to see which layer stops what.

## What changed since Stage 08

| File | Change |
|---|---|
| `scripts/install-linkerd-cni.sh` | **new, one-time node step**: Linkerd's iptables setup moves from a `linkerd-init` container in every Pod to a CNI plugin |
| `manifests/00-namespace.yaml` | Pod Security Admission labels: `enforce`/`warn`/`audit` = `restricted` |
| `manifests/05-serviceaccounts.yaml` | **new**: one ServiceAccount per tier, `automountServiceAccountToken: false` |
| `manifests/10-redis.yaml` | runs as uid 999, read-only root, drop ALL; `--requirepass` from Secret `redis-auth`; `REDISCLI_AUTH` for probes |
| `manifests/20-api.yaml` | uid 10001, read-only root (+ `/tmp` emptyDir), drop ALL; `REDIS_PASSWORD` from the Secret |
| `manifests/30-web.yaml` | uid 101, read-only root (+ `conf.d` and `/tmp` emptyDirs), drop ALL |
| `manifests/60-loadgen.yaml` | runs as `nobody` (65534), read-only root, drop ALL |
| `manifests/80-networkpolicies.yaml` | **new**: default-deny, then only Traefik→web→api→redis and loadgen→web |
| `scripts/create-redis-secret.sh` | **new**: random redis password, created in the cluster, never in a file |
| `scripts/trivy-scan.sh` | **new**: HIGH/CRITICAL scan of the three running images |
| `drills/intruder.yaml` | **new**: an unmeshed "attacker" Pod for S5 |

**Two steps before `kubectl apply`:** install linkerd-cni (S1) and create
the Secret (S2). Without the first, `restricted` rejects every Pod; without
the second, redis and api can't start.

## Learning objectives

- explain why Linkerd's default `linkerd-init` fails Pod Security `baseline` and `restricted`, and how a CNI plugin fixes it
- enforce PSA `restricted` on a namespace and read a rejection message
- give each tier its own ServiceAccount and turn off token automount
- run containers as non-root with a read-only root filesystem, and add only the writable paths they need
- keep a password out of git: generate it into a Secret, consume it with `secretKeyRef`
- write default-deny NetworkPolicies that still let a meshed app work
- explain what NetworkPolicy trusts (labels) and why a second layer (auth) matters
- scan images with Trivy and tell "rebuild fixes it" from "no fix exists yet"

## Before starting

Stage 08 running (or catch up with its manual):

```bash
cd ~/Documents/k3s-training/CAPSTONE/Stage09-Security
export NODE_IP=$(hostname -I | awk '{print $1}')
export PATH=$HOME/.linkerd2/bin:$PATH
kubectl -n capstone get pods              # 6 Pods 2/2
bash ../Stage05-Disruption-Backup-Restore/scripts/backup.sh ~/capstone-backups/pre-stage09
```

Take the backup: S2 changes redis for the first time since Stage 05.

---

## S1 — Why the mesh blocks Pod Security, and the fix (15 min)

Ask the API server what `restricted` would say about today's Pods,
without changing anything (`--dry-run=server`):

```bash
kubectl label --dry-run=server --overwrite ns capstone pod-security.kubernetes.io/enforce=baseline
kubectl -n capstone get pod -l app=api -o jsonpath='{.items[0].spec.initContainers[0].name}{" "}{.items[0].spec.initContainers[0].securityContext.capabilities}{"\n"}'
```

Expected:

```
Warning: api-69c945949f-bbq62 (and 5 other pods): non-default capabilities
linkerd-init {"add":["NET_ADMIN","NET_RAW"]}
```

Even `baseline`, the *lenient* profile, rejects them. The culprit is
Linkerd's `linkerd-init`: it needs NET_ADMIN to rewrite each Pod's iptables
so traffic flows through the proxy. The fix is to do that job once per
node instead of once per Pod, with the **linkerd-cni** plugin: a DaemonSet
in its own `linkerd-cni` namespace (allowed to be privileged) that hooks
into the node's CNI chain.

```bash
./scripts/install-linkerd-cni.sh
```

The script installs the DaemonSet with k3s's CNI paths, then runs
`linkerd upgrade --linkerd-cni-enabled` so new Pods are injected without
`linkerd-init`. Checks:

```bash
kubectl -n linkerd-cni get pods                      # 1/1 Running
sudo grep -o '"type": *"[a-z-]*"' /var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist
linkerd check | tail -1                              # Status check results are √
kubectl -n linkerd-viz rollout restart deploy        # viz Pods drop linkerd-init too
```

Expected: `flannel`, `portmap`, `bandwidth`, **`linkerd-cni`**.

> **Checkpoint S1:** you can say which container blocked `baseline`, which
> capability it needed, and where that job runs now.

## S2 — Password, then apply (10 min)

```bash
./scripts/create-redis-secret.sh
kubectl -n capstone get secret redis-auth
kubectl apply -f manifests/
kubectl -n capstone rollout status statefulset/redis
kubectl -n capstone rollout status deploy/api
kubectl -n capstone rollout status deploy/web
kubectl -n capstone rollout status deploy/loadgen
```

The apply prints this warning once. It's about the **old** Pods; the
rollout replaces them:

```
Warning: existing pods in namespace "capstone" violate the new PodSecurity enforce level "restricted:latest"
```

For ~30 s the api Pods may go NotReady: redis restarted with a password
before every api Pod had it. Then:

```bash
kubectl -n capstone get pods
curl -s -H 'Host: capstone.k3s.local' http://$NODE_IP/api/hits; echo
```

Expected: 6 Pods `2/2`, and the counter **continues** from before
(e.g. `{"hits":100337,...}`).

Where does the password live? Only in the cluster:

```bash
grep -rn requirepass manifests/10-redis.yaml   # "$(REDIS_PASSWORD)": a reference, not a value
kubectl -n capstone get secret redis-auth -o jsonpath='{.data.password}' | base64 -d | wc -c   # 48
```

> **Checkpoint S2:** counter works through the Ingress, and you can show
> the password isn't in any file in the repo.

## S3 — Check each hardening (10 min)

```bash
kubectl -n capstone get pods -o custom-columns='POD:.metadata.name,SA:.spec.serviceAccountName,INIT:.spec.initContainers[*].name,UID:.spec.securityContext.runAsUser'
kubectl -n capstone exec deploy/api -c api -- ls /var/run/secrets/kubernetes.io/serviceaccount
kubectl -n capstone exec deploy/api -c api -- id
kubectl -n capstone exec deploy/web -c web -- touch /usr/share/nginx/html/pwned
kubectl -n capstone exec redis-0 -c redis -- redis-cli GET hits
kubectl -n capstone exec redis-0 -c redis -- sh -c 'REDISCLI_AUTH= redis-cli GET hits'
kubectl -n capstone run stock-nginx --image=nginx:1.27-alpine
```

Expected:

```
POD                       SA        INIT                                      UID
api-6d655c4644-4wrvq      api       linkerd-network-validator,linkerd-proxy   10001
loadgen-749dfcb48-fdllm   loadgen   linkerd-network-validator,linkerd-proxy   65534
redis-0                   redis     linkerd-network-validator,linkerd-proxy   999
web-5567498448-2bcgz      web       linkerd-network-validator,linkerd-proxy   101
ls: cannot access '/var/run/secrets/kubernetes.io/serviceaccount': No such file or directory
uid=10001(app) gid=10001(app) groups=10001(app)
touch: /usr/share/nginx/html/pwned: Read-only file system
100349
NOAUTH Authentication required.
Error from server (Forbidden): pods "stock-nginx" is forbidden: violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false ..., unrestricted capabilities ..., runAsNonRoot != true ..., seccompProfile ...
```

Read the last one carefully: the stock `nginx` image is rejected **at
admission**, it never reaches a node. The capstone web image was built on
`nginx-unprivileged` back in Stage 01 for exactly this day.

`redis-cli GET hits` works without typing a password because the container
has `REDISCLI_AUTH` set. Blank it and redis refuses. That's also why
Stage 05's `backup.sh` keeps working unchanged: `kubectl exec` inherits the
container's environment.

> **Checkpoint S3:** you can name one thing each line above proves.

## S4 — NetworkPolicies: the allowed path, and the blocked ones (10 min)

```bash
kubectl -n capstone get networkpolicy
linkerd viz edges deploy -n capstone
```

Every edge is still `SECURED √` (mTLS). The identities now read `web`,
`api`, `loadgen`, not `default`.

Now try paths the policies don't allow, from **meshed** Pods:

```bash
kubectl -n capstone exec deploy/web -c web -- sh -c 'wget -q -T5 -O- http://api:8000/api/info; echo rc=$?'      # allowed
kubectl -n capstone exec deploy/loadgen -c loadgen -- sh -c 'wget -q -T5 -O- http://api:8000/api/info; echo rc=$?' # loadgen -> api
kubectl -n capstone exec deploy/web -c web -- sh -c 'wget -q -T5 -O- http://example.com >/dev/null; echo rc=$?'    # to the internet
kubectl -n capstone exec deploy/web -c web -- sh -c 'printf "PING\r\n" | nc -w5 redis 6379; echo rc=$?'            # web -> redis
```

Expected:

```
{"pod":"api-6d655c4644-4wrvq","redis":"redis:6379","version":"1.0.0"}
rc=0
wget: server returned error: HTTP/1.1 504 Gateway Timeout
rc=1
wget: server returned error: HTTP/1.1 502 Bad Gateway
rc=1
rc=0
```

Blocked, but not how you might expect. A meshed container's connection
goes to **its own proxy** first, which always accepts. The proxy's onward
connection is what the policy blocks, so HTTP callers get a 502/504, and
`nc` to redis gets a connection with **no `PONG`**, closed by the proxy.

> **Checkpoint S4:** the counter still works, and you can explain why a
> blocked meshed call returns 502/504 instead of timing out.

## S5 — Drill: play the attacker (10 min)

[drills/intruder.yaml](drills/intruder.yaml) is a Pod **without** the
mesh, inside `capstone`. It passes PSA `restricted` (Pod Security limits
*what* a Pod can do, not *who* may create one: that's RBAC).

```bash
kubectl apply -f drills/intruder.yaml
kubectl -n capstone wait --for=condition=Ready pod/intruder
kubectl -n capstone exec intruder -- sh -c 'time nc -w5 redis-0.redis 6379 </dev/null; echo rc=$?'
kubectl -n capstone exec intruder -- sh -c 'wget -q -T5 -O- http://web/; echo rc=$?'
```

Expected: both fail in about **1 second**:

```
real	0m 1.15s
rc=1
wget: can't connect to remote host (10.43.62.150): Connection refused
```

k3s's policy controller **rejects** blocked packets, so you see `Connection
refused` quickly. (CNIs like Calico drop them silently: a timeout instead.)

Now the attacker changes one label:

```bash
kubectl -n capstone label pod intruder app=api --overwrite
kubectl -n capstone exec intruder -- sh -c 'printf "PING\r\n" | nc -w3 redis-0.redis 6379; echo rc=$?'
```

Expected:

```
-NOAUTH Authentication required.
```

The NetworkPolicy let it through: it trusts **labels**, and whoever can
edit a Pod can set any label. The redis password is what still stopped
it. That's defense in depth: two independent layers, so one mistake isn't
a breach. (A side effect worth seeing: the api HPA also counts any Pod
labelled `app=api`, and logs `container api not found in Pod intruder`.)

```bash
kubectl delete -f drills/intruder.yaml
```

> **Checkpoint S5:** you can say which layer stopped the intruder before
> and after the relabel, and what would make the label trick impossible
> (RBAC: no `patch pods` for untrusted users; Linkerd authorization
> policies keyed on the mTLS identity instead of labels).

## S6 — Scan the images (10 min)

```bash
./scripts/trivy-scan.sh --summary
```

The first run downloads the vulnerability DB (~1 min). Expected (numbers
change as new CVEs are published):

```
=== localhost:5000/capstone-web:1.0.0
  HIGH: 36  CRITICAL: 2
=== localhost:5000/capstone-api:1.0.0
  HIGH: 44  CRITICAL: 0
=== redis:7-alpine
  HIGH: 0  CRITICAL: 0
```

Look closer with `./scripts/trivy-scan.sh` (full table). The two images
have very different stories:

| Image | Where the CVEs are | Fixed version? | What to do |
|---|---|---|---|
| capstone-web | Alpine 3.21 OS packages (openssl, expat, libpng...) | **all** of them | rebuild on a current `nginx-unprivileged` base; Day 13 ships this as 1.1.0 |
| capstone-api | Debian OS packages (util-linux libs...) | **none yet** | nothing to upgrade to: track them, or shrink the base (e.g. distroless) so the packages aren't there at all |

None were in the app's own Python packages. A scan is only as current as
the day you ran it: the images didn't change since Stage 01, the CVE
database did.

> **Checkpoint S6:** you can say which image a rebuild would fix today and
> which it wouldn't.

---

## Troubleshooting

| Symptom | Likely cause / check |
|---|---|
| apply: `forbidden: violates PodSecurity "restricted:latest"` listing `linkerd-init` | S1 not done, or done after these Pods were created: run `install-linkerd-cni.sh`, then `kubectl -n capstone rollout restart deploy` and `... statefulset` |
| redis/api `CreateContainerConfigError` | Secret `redis-auth` missing: `./scripts/create-redis-secret.sh` |
| api NotReady, `/ready` says `AuthenticationError` or `NOAUTH` | api and redis see different passwords (Secret recreated under a running redis). `kubectl -n capstone rollout restart statefulset/redis deploy/api` |
| web `CrashLoopBackOff`, log mentions `/etc/nginx/conf.d` or `Read-only file system` | a writable emptyDir is missing from `30-web.yaml` (`conf-d` and `tmp`) |
| everything 2/2 but the site returns 502/504 | a NetworkPolicy blocks Traefik→web: check `kubectl -n kube-system get pods -l app.kubernetes.io/name=traefik --show-labels` matches the `web` policy |
| proxies stuck `1/2`, logs mention identity/destination | the `allow-dns-and-linkerd` policy is missing or edited: the proxy can't reach the Linkerd control plane |
| `linkerd viz edges` / dashboard empty for capstone | viz can't scrape port 4191: same policy, the `ingress` from `linkerd-viz` |
| Trivy: `http: server gave HTTP response to HTTPS client` | the `--insecure` flag was dropped; the local registry is plain HTTP |

## Before you leave — keep it running

Keep linkerd-cni and the Secret: every later stage assumes both. To catch
up later:

```bash
cd ~/Documents/k3s-training/CAPSTONE/Stage09-Security
./scripts/install-linkerd-cni.sh                 # once per VM
kubectl apply -f manifests/00-namespace.yaml
./scripts/create-redis-secret.sh
kubectl apply -f manifests/
```
