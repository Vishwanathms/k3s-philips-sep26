# ex06 — verified run

Captured **2026-09-10** on k3s `v1.36.4+k3s1`, namespace `day02-networking`.
Result: **PASS** — before the policy both clients reached `web`; after it,
only the labeled `allowed-client` did.

Enforcement is done by the network-policy controller k3s embeds (no extra
install, no `--disable-network-policy` flag on this cluster):

```console
$ journalctl -u k3s | grep -i "network policy controller" | head -1
Starting network policy controller version v2.6.3-k3s1, built on 2026-08-27, go1.26.7
```

Three consecutive rounds after applying the policy: `allowed-client` served
the page every time, `blocked-client` got `Connection refused` every time.

```console
$ kubectl exec -n day02-networking allowed-client -- wget -T 3 -qO- http://web >/dev/null && echo allowed-after=yes
allowed-after=yes

$ kubectl exec -n day02-networking blocked-client -- wget -T 3 -qO- http://web >/dev/null || echo blocked-after=expected
wget: can't connect to remote host (10.43.88.168): Connection refused
blocked-after=expected
```

The NetworkPolicy selector and allow rule were confirmed with:

```console
$ kubectl describe networkpolicy web-allow-approved-clients -n day02-networking
PodSelector: app=web
Allowing ingress traffic:
  To Port: 80/TCP
  From:
    PodSelector: access=web-allowed
Policy Types: Ingress
```

## Cleanup

```console
$ kubectl delete namespace day02-networking
```

The live test namespace was deleted after capture; a follow-up API query
returned `namespaces "day02-networking" not found`.
