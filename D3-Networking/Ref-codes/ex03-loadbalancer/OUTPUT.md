# ex03 — verified run

Captured **2026-09-10** on k3s `v1.36.4+k3s1`, namespace `day02-networking`.
Result: **PASS** — k3s's ServiceLB assigned an `EXTERNAL-IP` and the Service
was reachable on its port.

```console
$ kubectl get svc -n day02-networking
NAME               TYPE           CLUSTER-IP      EXTERNAL-IP       PORT(S)
web-loadbalancer   LoadBalancer   10.43.143.221   192.168.230.103   8088:32091/TCP
```

The k3s ServiceLB workload was running for this Service:

```console
$ kubectl get pods -n kube-system -o wide | grep svclb-web-loadbalancer
svclb-web-loadbalancer-61737b88-whtwl   1/1   Running   0   47s   10.42.0.57   lab-g2-vm2
```

```console
$ curl -s http://192.168.230.103:8088/ | head -1
<!DOCTYPE html>
```
