# Capstone stage 09 — verified run

Captured **2026-09-29** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
Linkerd `edge-26.9.3`, applied over a running Stage 08 (meshed, HPA on api,
PriorityClasses). Backup first: `~/capstone-backups/pre-stage09`, counter
99662. Result: **PASS** for S1–S6.

> Findings that shaped the manual:
> - `linkerd-init` fails **`baseline`**, not just `restricted` (NET_ADMIN
>   isn't in baseline's allowed list), so relaxing the namespace to
>   baseline was never an option. Hence linkerd-cni.
> - With linkerd-cni, the injector gives `linkerd-proxy` `drop: [ALL]`
>   and the new `linkerd-network-validator` init container is already
>   restricted-compliant: a meshed Pod is admitted under `restricted`
>   (tested in a scratch namespace first).
> - Blocked **meshed** calls don't time out: the caller's own proxy
>   answers 502/504. Blocked **unmeshed** calls get `Connection refused` in
>   ~1 s, because k3s's kube-router policy controller rejects, not drops.
> - A raw TCP connect from a meshed Pod "succeeds" even when blocked (the
>   local proxy accepts it). Test with real traffic (HTTP, redis `PING`).

## S1 — before: PSA dry run, then linkerd-cni

```console
$ kubectl label --dry-run=server --overwrite ns capstone pod-security.kubernetes.io/enforce=restricted
Warning: existing pods in namespace "capstone" violate the new PodSecurity enforce level "restricted:latest"
Warning: api-69c945949f-bbq62 (and 5 other pods): allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
$ kubectl label --dry-run=server --overwrite ns capstone pod-security.kubernetes.io/enforce=baseline
Warning: existing pods in namespace "capstone" violate the new PodSecurity enforce level "baseline:latest"
Warning: api-69c945949f-bbq62 (and 5 other pods): non-default capabilities

# initContainers of an api Pod
linkerd-init  sc={"allowPrivilegeEscalation":false,"capabilities":{"add":["NET_ADMIN","NET_RAW"]},...,"runAsNonRoot":true,"runAsUser":65534,...}
linkerd-proxy restartPolicy=Always
```

```console
$ ./scripts/install-linkerd-cni.sh
[1/4] install the linkerd-cni DaemonSet
...
[3/4] tell the control plane: inject without linkerd-init from now on
...
deployment "linkerd-proxy-injector" successfully rolled out
deployment "linkerd-destination" successfully rolled out
deployment "linkerd-identity" successfully rolled out

$ kubectl -n linkerd-cni get ds,pods
NAME                         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
daemonset.apps/linkerd-cni   1         1         1       1            1
pod/linkerd-cni-7qgd5        1/1     Running   0          78s

$ sudo cat .../10-flannel.conflist | python3 -m json.tool | grep '"type"'
            "type": "flannel"
            "type": "portmap"
            "type": "bandwidth"
            "type": "linkerd-cni"
$ linkerd check | tail -1
Status check results are √

$ kubectl -n linkerd-viz rollout restart deploy
...
deployment "tap-injector" successfully rolled out
```

A web Pod restarted after this has, in place of `linkerd-init`:

```
linkerd-network-validator sc={"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":65534,"runAsNonRoot":true,"runAsUser":65534,"seccompProfile":{"type":"RuntimeDefault"}}
linkerd-proxy             sc={"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true,"runAsUser":2102,"seccompProfile":{"type":"RuntimeDefault"}}
```

## S2 — secret + apply

```console
$ ./scripts/create-redis-secret.sh
secret/redis-auth created
secret/redis-auth labeled
$ kubectl apply -f manifests/
Warning: existing pods in namespace "capstone" violate the new PodSecurity enforce level "restricted:latest"
Warning: api-69c945949f-bbq62 (and 5 other pods): allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/capstone configured
...
serviceaccount/web created
serviceaccount/api created
serviceaccount/redis created
serviceaccount/loadgen created
statefulset.apps/redis configured
deployment.apps/api configured
deployment.apps/web configured
deployment.apps/loadgen configured
networkpolicy.networking.k8s.io/default-deny created
networkpolicy.networking.k8s.io/allow-dns-and-linkerd created
networkpolicy.networking.k8s.io/web created
networkpolicy.networking.k8s.io/api created
networkpolicy.networking.k8s.io/redis created
networkpolicy.networking.k8s.io/loadgen created
... all four rollouts complete ...

$ kubectl -n capstone get pods
NAME                      READY   STATUS    RESTARTS   AGE
api-6d655c4644-4wrvq      2/2     Running   0          66s
api-6d655c4644-g2gng      2/2     Running   0          34s
loadgen-749dfcb48-fdllm   2/2     Running   0          54s
redis-0                   2/2     Running   0          57s
web-5567498448-2bcgz      2/2     Running   0          48s
web-5567498448-grcjl      2/2     Running   0          64s

$ curl -s -H 'Host: capstone.k3s.local' http://192.168.230.103/api/hits
{"hits":100337,"pod":"api-6d655c4644-4wrvq","version":"1.0.0"}
{"hits":100338,"pod":"api-6d655c4644-g2gng","version":"1.0.0"}
$ curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: capstone.k3s.local' http://192.168.230.103/
200
```

Counter continued from the pre-stage backup (99662, plus loadgen's ~2/s).
The old loadgen Pod showed `0/2 Error` briefly while terminating.

## S3 — hardening checks

```console
POD                       SA        INIT                                      UID
api-6d655c4644-4wrvq      api       linkerd-network-validator,linkerd-proxy   10001
api-6d655c4644-g2gng      api       linkerd-network-validator,linkerd-proxy   10001
loadgen-749dfcb48-fdllm   loadgen   linkerd-network-validator,linkerd-proxy   65534
redis-0                   redis     linkerd-network-validator,linkerd-proxy   999
web-5567498448-2bcgz      web       linkerd-network-validator,linkerd-proxy   101
web-5567498448-grcjl      web       linkerd-network-validator,linkerd-proxy   101

$ kubectl -n capstone exec deploy/api -c api -- ls /var/run/secrets/kubernetes.io/serviceaccount
ls: cannot access '/var/run/secrets/kubernetes.io/serviceaccount': No such file or directory
$ kubectl -n capstone exec deploy/api -c api -- id
uid=10001(app) gid=10001(app) groups=10001(app)
$ kubectl -n capstone exec deploy/web -c web -- touch /usr/share/nginx/html/pwned
touch: /usr/share/nginx/html/pwned: Read-only file system
$ kubectl -n capstone exec redis-0 -c redis -- redis-cli GET hits
100349
$ kubectl -n capstone exec redis-0 -c redis -- sh -c 'REDISCLI_AUTH= redis-cli GET hits'
AUTH failed: WRONGPASS invalid username-password pair or user is disabled.
NOAUTH Authentication required.
$ kubectl -n capstone run stock-nginx --image=nginx:1.27-alpine
Error from server (Forbidden): pods "stock-nginx" is forbidden: violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "stock-nginx" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (containers "linkerd-proxy", "stock-nginx" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "stock-nginx" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "stock-nginx" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```

Stage 05's backup still works unchanged (`kubectl exec` inherits
`REDISCLI_AUTH`):

```console
$ bash ../Stage05-Disruption-Backup-Restore/scripts/backup.sh ~/capstone-backups/stage09-check
...
$ grep hits ~/capstone-backups/stage09-check/backup-info.txt
hits:   100616
```

## S4 — policies, meshed callers

```console
$ linkerd viz edges deploy -n capstone
SRC          DST       SRC_NS        DST_NS     SECURED
loadgen      web       capstone      capstone   √
web          api       capstone      capstone   √
prometheus   api       linkerd-viz   capstone   √
prometheus   loadgen   linkerd-viz   capstone   √
prometheus   web       linkerd-viz   capstone   √

# web -> api (allowed)
{"pod":"api-6d655c4644-4wrvq","redis":"redis:6379","version":"1.0.0"}
rc=0
# loadgen -> api (blocked)
wget: server returned error: HTTP/1.1 504 Gateway Timeout
rc=1
# web -> internet (blocked)
wget: server returned error: HTTP/1.1 502 Bad Gateway
rc=1
# api -> internet (blocked), python urllib
internet: HTTP Error 502: Bad Gateway 0.8 s
# web -> redis (blocked): connection to the local proxy, no PONG
rc=0
# api -> redis (allowed), with the password
api->redis PING: True
```

(`api -> redis` is opaque TCP, so `viz edges` doesn't list it: same as
in Stage 06.)

## S5 — intruder

```console
$ kubectl apply -f drills/intruder.yaml
pod/intruder created
$ kubectl -n capstone wait --for=condition=Ready pod/intruder --timeout=60s
pod/intruder condition met
$ kubectl -n capstone exec intruder -- sh -c 'time nc -w5 redis-0.redis 6379 </dev/null; echo rc=$?'
Command exited with non-zero status 1
real	0m 1.15s
rc=1
$ kubectl -n capstone exec intruder -- sh -c 'time wget -q -T5 -O- http://web/ ; echo rc=$?'
wget: can't connect to remote host (10.43.62.150): Connection refused
real	0m 1.12s
rc=1
$ kubectl -n capstone label pod intruder app=api --overwrite
pod/intruder labeled
$ kubectl -n capstone exec intruder -- sh -c 'printf "PING\r\n" | nc -w3 redis-0.redis 6379; echo rc=$?'
-NOAUTH Authentication required.
rc=0
$ kubectl delete -f drills/intruder.yaml
pod "intruder" deleted from capstone namespace
```

While the intruder carried `app=api`, the HPA's selector matched it:

```
Warning  FailedGetContainerResourceMetric  horizontal-pod-autoscaler  failed to get cpu utilization: container api not found in Pod intruder
```

(`busybox nslookup redis` returned non-zero in this Pod although name
resolution worked for `nc`/`wget`: a busybox quirk, so the manual doesn't
use it.)

## S6 — Trivy (aquasec/trivy:0.74.0)

```console
$ ./scripts/trivy-scan.sh --summary
=== localhost:5000/capstone-web:1.0.0
  HIGH: 36  CRITICAL: 2
=== localhost:5000/capstone-api:1.0.0
  HIGH: 44  CRITICAL: 0
=== redis:7-alpine
  HIGH: 0  CRITICAL: 0
```

Per package (from the JSON output):

```
capstone-web (alpine 3.21.3) | 38 vulns, 38 with a fix | libcrypto3(8), libssl3(8), libexpat(7), libpng(6), libxml2(4)
    CRITICAL CVE-2026-31789 libcrypto3 3.3.3-r0 -> 3.3.7-r0
    CRITICAL CVE-2026-31789 libssl3 3.3.3-r0 -> 3.3.7-r0
capstone-api (debian 13.7)   | 44 vulns, 0 with a fix  | bsdutils(4), libblkid1(4), liblastlog2-2(4), libmount1(4), libsmartcols1(4)
```

No findings in the api's Python packages.

During the scans the node was at ~87% CPU (an unrelated Docker Compose
stack also runs on this VM). The api HPA briefly scaled 2 → 5 and back to 2;
two of the extra api Pods logged startup-probe timeouts while the node was
busy. Nothing needed fixing.
