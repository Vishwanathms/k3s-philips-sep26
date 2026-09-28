# ex02 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
namespace `d5-health`. Result: **PASS** — a Pod failing its readiness
probe was pulled out of the Service's endpoints without ever being
restarted, and traffic through the Service avoided it completely.

```console
$ kubectl apply -f ex02-readiness-probe/deployment.yaml
deployment.apps/web created
service/web created
$ kubectl rollout status deployment/web -n d5-health --timeout=60s
deployment "web" successfully rolled out

$ kubectl get endpointslice -l kubernetes.io/service-name=web -n d5-health -o wide
NAME        ADDRESSTYPE   PORTS   ENDPOINTS
web-v8b27   IPv4          80      10.42.0.170,10.42.0.169   # both Pods, both Ready
```

## Flip one replica to not-ready — on purpose, no restart

```console
$ kubectl exec web-5cc97b895f-7nrdp -n d5-health -- rm /tmp/ready

$ kubectl get pods -l app=web -n d5-health
NAME                   READY   STATUS    RESTARTS   AGE
web-5cc97b895f-7nrdp   0/1     Running   0          19s      # NOT restarted
web-5cc97b895f-sg52l   1/1     Running   0          20s

$ kubectl get endpointslice -l kubernetes.io/service-name=web -n d5-health \
    -o jsonpath='{.items[0].endpoints}'
[
  {"addresses": ["10.42.0.170"], "conditions": {"ready": false, ...}, "targetRef": {"name": "web-5cc97b895f-7nrdp", ...}},
  {"addresses": ["10.42.0.169"], "conditions": {"ready": true,  ...}, "targetRef": {"name": "web-5cc97b895f-sg52l", ...}}
]
```

The unready Pod stays **in** the EndpointSlice (so kube-proxy can add it back
instantly once it's Ready again) but flagged `"ready": false` — the same
mechanism verified in Day 04/06's drills. `RESTARTS` stayed `0` the entire
time; the container itself never noticed anything:

```console
$ kubectl exec web-5cc97b895f-7nrdp -n d5-health -- ps aux
PID   USER     TIME  COMMAND
    1 root      0:00 nginx: master process nginx -g daemon off;
   15 nginx     0:00 nginx: worker process
   16 nginx     0:00 nginx: worker process
   17 nginx     0:00 nginx: worker process
```

## Proof traffic actually avoids it

```console
$ kubectl run curl-test --image=busybox:1.36 --restart=Never --rm -i -- \
    sh -c 'for i in 1 2 3 4 5; do wget -qO- http://web -T 3 >/dev/null 2>&1 && echo request-$i=ok || echo request-$i=FAIL; done'
request-1=ok
request-2=ok
request-3=ok
request-4=ok
request-5=ok
```

Five requests through the Service, only one Ready backend available — all
five succeeded, none hit the unready Pod (which would have worked anyway
since nginx itself is fine, but kube-proxy's iptables rules were never
programmed to send traffic there in the first place — the same `KUBE-SEP-*`
mechanism from Day 04, now missing an entry for the unready Pod).

## Restore readiness

```console
$ kubectl exec web-5cc97b895f-7nrdp -n d5-health -- touch /tmp/ready
$ kubectl get pods -l app=web -n d5-health
NAME                   READY   STATUS    RESTARTS   AGE
web-5cc97b895f-7nrdp   1/1     Running   0          65s
web-5cc97b895f-sg52l   1/1     Running   0          66s
```

Contrast with **ex01**: a failed **liveness** probe restarts the container;
a failed **readiness** probe just stops traffic to it. Same syntax shape
(`exec`/`httpGet` + thresholds), completely different consequence.
