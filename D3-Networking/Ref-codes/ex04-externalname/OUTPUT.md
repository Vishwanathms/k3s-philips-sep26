# ex04 — verified run

Captured **2026-09-10** on k3s `v1.36.4+k3s1`, namespace `d3-networking`.
Result: **PASS** — the `ExternalName` Service returned a CNAME, and traffic
to it reached the aliased Service's Pods.

```console
$ kubectl get svc -n d3-networking
NAME        TYPE           CLUSTER-IP   EXTERNAL-IP                              PORT(S)
web-alias   ExternalName   <none>       web.d3-networking.svc.cluster.local   <none>

$ kubectl exec -n d3-networking dns-client -- nslookup web-alias.d3-networking.svc.cluster.local
web-alias.d3-networking.svc.cluster.local canonical name = web.d3-networking.svc.cluster.local
Name:      web.d3-networking.svc.cluster.local
Address:   10.43.88.168
```

```console
$ kubectl exec -n d3-networking allowed-client -- wget -T 3 -qO- http://web-alias
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```
