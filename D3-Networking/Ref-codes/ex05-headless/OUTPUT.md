# ex05 — verified run

Captured **2026-09-10** on k3s `v1.36.4+k3s1`, namespace `day02-networking`.
Result: **PASS** — DNS returned the individual Pod IPs directly, not a
ClusterIP.

```console
$ kubectl get svc -n day02-networking
NAME           TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)
web-headless   ClusterIP   None         <none>        80/TCP

$ kubectl exec -n day02-networking dns-client -- nslookup web-headless.day02-networking.svc.cluster.local
Name:      web-headless.day02-networking.svc.cluster.local
Address:   10.42.0.59
Name:      web-headless.day02-networking.svc.cluster.local
Address:   10.42.0.58
```

The EndpointSlice held the same two Pod IPs:

```console
$ kubectl get endpointslice -n day02-networking -l kubernetes.io/service-name=web-headless -o jsonpath='...'
10.42.0.58
10.42.0.59
```
