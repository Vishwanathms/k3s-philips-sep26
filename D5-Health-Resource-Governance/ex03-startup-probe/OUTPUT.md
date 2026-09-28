# ex03 — verified run

Captured **2026-09-13** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
namespace `d5-health`. Result: **PASS** — the identical slow-starting
container (20s to become healthy) crash-loops forever without a
`startupProbe`, and starts cleanly with one.

Both Pods run the exact same command
(`sleep 20; touch /tmp/healthy; sleep 600`) and the exact same liveness
check (`cat /tmp/healthy`, `periodSeconds: 5`, `failureThreshold: 1`) — the
only difference is `slow-starter-good` also has a `startupProbe` with a 30s
budget (`periodSeconds: 5 × failureThreshold: 6`).

```console
$ kubectl apply -f ex03-startup-probe/bad-no-startup-probe.yaml
$ kubectl apply -f ex03-startup-probe/good-with-startup-probe.yaml
```

## `slow-starter-bad`: never gets a chance to finish starting

```console
$ kubectl get pod slow-starter-bad
NAME               READY   RESTARTS      AGE
slow-starter-bad   1/1     2 (34s ago)   105s

$ kubectl describe pod slow-starter-bad
Events:
  Warning  Unhealthy  8s (x3 over 78s)   kubelet   Liveness probe failed: cat: can't open '/tmp/healthy': No such file or directory
  Normal   Killing    8s (x3 over 78s)   kubelet   Container app failed liveness probe, will be restarted
  Normal   Pulled     13s (x3 over 82s)  kubelet   ...
  Normal   Created    13s (x3 over 82s)  kubelet   Container created
  Normal   Started    12s (x3 over 82s)  kubelet   Container started
```

`(x3 over 82s)` on `Started`: the liveness probe's very first check happens
at `t≈5s` — long before the file appears at `t=20s` — so `failureThreshold: 1`
kills it immediately. Every restart resets the container's own 20s countdown
back to zero. This Pod **cannot ever finish starting** without help; it will
crash-loop indefinitely (with growing `CrashLoopBackOff` delays between
attempts — restarts visibly slow down over time).

## `slow-starter-good`: the same startup, protected

```console
$ kubectl get pod slow-starter-good
NAME                READY   RESTARTS   AGE
slow-starter-good   1/1     0          105s

$ kubectl describe pod slow-starter-good
Events:
  Normal   Started    103s   kubelet   Container started
  Warning  Unhealthy  85s (x4 over 100s)   kubelet   Startup probe failed: cat: can't open '/tmp/healthy': No such file or directory
```

Four **startup**-probe failures (at `t≈5,10,15,20s` — all before the file
exists) — but note the event reason is `Unhealthy`/`Startup probe failed`,
**not** `Killing`. While a `startupProbe` is defined and not yet successful,
the liveness probe is not evaluated at all, so nothing restarts the
container while it's legitimately still starting. By the 5th attempt
(`t≈25s`), the file exists, the startup probe passes once, and liveness
takes over — `RESTARTS` stayed at `0` for the entire capture window (105s,
well past the point where `slow-starter-bad` had already failed twice).

## The takeaway

Same app, same liveness check, same 20s startup time — one Pod is
permanently broken, the other is perfectly healthy. The only difference is
one `startupProbe` block.
