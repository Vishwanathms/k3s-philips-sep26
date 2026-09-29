# ex03 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`.
Result: **PASS** — real, executed (not dry-run) certificate rotation. New
serials, new validity dates, old certs auto-backed-up, ~2s of API downtime,
cluster fully healthy afterward.

## Before

```console
$ sudo cat /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt | openssl x509 -noout -serial -dates
serial=43B6430A80F15C47
notBefore=Sep  8 05:16:31 2026 GMT
notAfter=Sep  8 05:16:31 2027 GMT
```

## Rotate

```console
$ sudo k3s certificate rotate
level=info msg="Server detected, rotating agent and server certificates"
level=info msg="Rotating dynamic listener certificate"
level=info msg="Rotating certificates for controller-manager"
level=info msg="Rotating certificates for etcd"
level=info msg="Rotating certificates for scheduler"
level=info msg="Rotating certificates for kube-proxy"
level=info msg="Rotating certificates for admin"
level=info msg="Rotating certificates for cloud-controller"
level=info msg="Rotating certificates for supervisor"
level=info msg="Rotating certificates for kubelet"
level=info msg="Rotating certificates for k3s-controller"
level=info msg="Rotating certificates for api-server"
level=info msg="Rotating certificates for auth-proxy"
level=info msg="Successfully backed up certificates to /var/lib/rancher/k3s/server/tls-1789321189,
  please restart k3s server or agent to rotate certificates"
```

`rotate` writes new certs to disk and — unprompted — backs up the entire
previous `tls/` directory to a timestamped `tls-<epoch>/` sibling. The new
certs aren't in effect until the service restarts.

```console
$ sudo systemctl restart k3s
$ kubectl get nodes    # polled every 2s
NAME         STATUS   ROLES           AGE     VERSION
lab-g2-vm2   Ready    control-plane   5d11h   v1.36.4+k3s1
```

The API was back and answering within **~2 seconds** of the restart.

## After

```console
$ sudo cat /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt | openssl x509 -noout -serial -dates
serial=05B85C75E3372D65                  # <- different from before
notBefore=Sep 13 16:40:01 2026 GMT       # <- reissued today
notAfter=Sep 13 16:40:01 2027 GMT

$ sudo ls /var/lib/rancher/k3s/server/ | grep tls
tls
tls-1789321189                           # <- k3s's own automatic backup of the old certs
```

```console
$ kubectl get pods -n kube-system --no-headers | awk '{print $1, $3}'
coredns-...                    Running
csi-nfs-controller-...         Running
csi-nfs-node-...                Running
local-path-provisioner-...     Running
metrics-server-...             Running
svclb-traefik-...               Running
traefik-...                     Running
```

Every workload — Ingress, DNS, storage provisioning, metrics, the NFS CSI
driver — came back healthy with no manual intervention beyond the restart.

## Why this session's own `kubectl` never noticed

This terminal's `~/.kube/config` (copied once, at install time, in Day 00)
still has the **original**, pre-rotation client certificate embedded — and
it kept working through the whole rotation. `k3s certificate rotate` only
reissues **leaf** certificates; it does not touch the CA
(`rotate-ca` is a separate, much more disruptive command). Since the old
client cert is still validly signed by the same, unchanged CA, the API
server keeps trusting it. Rotation invalidates nothing already issued — it
only changes what gets issued *next*, which is exactly why it's safe to run
routinely rather than only when a cert is about to expire.
