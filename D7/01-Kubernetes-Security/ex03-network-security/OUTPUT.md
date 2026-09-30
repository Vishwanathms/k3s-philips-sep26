# Output — ex03 Network Security

Real run against `lab-g2-vm2`, 2026-09-14.

## Baseline: everything reachable, no policy at all

```
$ kubectl exec netcheck -n day11-security -- wget -q -T3 -O- http://web
<!DOCTYPE html>...Welcome to nginx!...
$ kubectl exec netcheck -n day11-security -- nc -w3 db 5432
db-response
```

Default Kubernetes networking is flat and fully open — any Pod can reach
any other Pod/Service in the cluster. This is the starting posture every
namespace should be hardened away from.

## default-deny-all: everything blocked, including DNS

```
$ kubectl apply -f deny-all.yaml
$ kubectl exec netcheck -n day11-security -- wget -q -T3 -O- http://web
wget: bad address 'web'

$ kubectl exec netcheck -n day11-security -- wget -q -T3 -O- http://10.43.103.70   # by IP, bypassing DNS
wget: can't connect to remote host (10.43.103.70): Connection refused
```

An empty `podSelector: {}` with `policyTypes: [Ingress, Egress]` and no
rules means "deny everything, including this Pod's own DNS lookups" — that
first failure ("bad address") isn't a NetworkPolicy log line, it's DNS
resolution itself failing because egress to CoreDNS (port 53) is now
blocked too. Testing by raw ClusterIP isolates that: **`Connection refused`,
not a timeout** — this k3s's embedded network policy controller
(kube-router) actively REJECTs blocked traffic rather than silently
dropping it, the same finding as Day-04's dataplane investigation.

## A subtle, real finding: NetworkPolicy needs BOTH sides to agree

```
$ kubectl apply -f allow-web-ingress.yaml -f allow-dns-egress.yaml
# allow-web-ingress: web's ingress now allows traffic from anything in the namespace
# allow-dns-egress:  every Pod's egress now allows DNS (port 53)

$ kubectl exec netcheck -n day11-security -- wget -q -T3 -O- http://web
wget: can't connect to remote host (10.43.103.70): Connection refused
```

**Still refused** — DNS resolved the name fine this time (the error
changed from "bad address" to "can't connect", proof DNS itself now works),
but the connection was still rejected. `allow-web-ingress` only authorizes
the **destination**'s ingress side; `netcheck` (the source) still has no
egress rule permitting port 80 traffic anywhere. NetworkPolicy is not "an
allow rule on either end is enough" — **both** the source Pod's egress
policy and the destination Pod's ingress policy must independently permit
the exact same connection, or it's refused.

```
$ kubectl apply -f allow-egress-to-web.yaml
$ kubectl exec netcheck -n day11-security -- wget -q -T3 -O- http://web
<!DOCTYPE html>...Welcome to nginx!...          # now works - both sides authorized

$ kubectl exec netcheck -n day11-security -- nc -w3 db 5432
command terminated with exit code 1              # db was never authorized on either side - still fully blocked
```

## Why this matters

This is the single most common real-world NetworkPolicy mistake: writing an
`ingress` rule on the "allow" side of a connection and assuming that's
enough, then being confused when traffic is still refused because the
caller's own `egress` policy (often a separate, easy-to-forget
`default-deny` applied namespace-wide) never explicitly permitted it.

## Cleanup

```
$ kubectl delete -f deployment.yaml -f deny-all.yaml -f allow-web-ingress.yaml -f allow-egress-to-web.yaml
$ kubectl delete pod netcheck -n day11-security
```
