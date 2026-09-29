# Prerequisites — installing VPA on your own lab

Run this **once per student cluster**, before Lab 3 in
[../LAB-MANUAL.md](../LAB-MANUAL.md). Unlike `metrics-server` (bundled with
k3s since Day 00), the Vertical Pod Autoscaler is **not** part of k3s — you
install it yourself from the upstream `kubernetes/autoscaler` project. If
you already ran this on your VM for an earlier session, skip to
[Verify](#verify) to confirm it's still there.

## Step 0 — confirm what you already have

```bash
kubectl get nodes                              # your node is Ready
kubectl top node                                # metrics-server works (needed by VPA and HPA)
kubectl get crd | grep autoscaling.k8s.io       # empty the first time - that's expected
helm version --short                            # helm v3.x is already installed on this image
```

If `kubectl top node` errors or hangs, fix that first — VPA depends on the
same metrics pipeline HPA does. `kubectl -n kube-system get pods -l k8s-app=metrics-server`
should show one Running Pod.

## Step 1 — install VPA

Either run the one script:

```bash
cd Day-09-Performance-Scaling/ex03-vertical-pod-autoscaler
./install-vpa.sh
```

...or do it by hand (what the script runs):

```bash
git clone --filter=blob:none --sparse https://github.com/kubernetes/autoscaler.git /tmp/autoscaler
cd /tmp/autoscaler
git sparse-checkout set vertical-pod-autoscaler

helm install vpa vertical-pod-autoscaler/charts/vertical-pod-autoscaler -n kube-system

kubectl -n kube-system rollout status deployment/vpa-recommender --timeout=90s
kubectl -n kube-system rollout status deployment/vpa-updater --timeout=90s
kubectl -n kube-system rollout status deployment/vpa-admission-controller --timeout=90s
```

This installs three Deployments into `kube-system` — `vpa-recommender`
(watches usage, produces recommendations), `vpa-updater` (evicts Pods to
apply them when `updateMode: Recreate`), and `vpa-admission-controller` (a
webhook that rewrites Pod specs on creation) — plus the
`VerticalPodAutoscaler` and `VerticalPodAutoscalerCheckpoint` CRDs.

## Verify

```bash
kubectl get crd | grep autoscaling.k8s.io
# verticalpodautoscalercheckpoints.autoscaling.k8s.io
# verticalpodautoscalers.autoscaling.k8s.io

kubectl -n kube-system get pods -l app.kubernetes.io/name=vertical-pod-autoscaler
# three Pods (recommender, updater, admission-controller), all 1/1 Running
```

Both commands returning output confirms you're ready for Lab 3.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `git clone` hangs or fails | no outbound internet from the lab VM | check with your instructor — this lab needs GitHub access once, at install time only |
| `helm install` fails: `cannot re-use a name that is still in use` | VPA already installed from a previous session | `helm -n kube-system list \| grep vpa` to confirm, then skip to [Verify](#verify) |
| admission-controller Pod stuck `Pending` / `CrashLoopBackOff` | webhook cert generation race on a slow VM | `kubectl -n kube-system rollout restart deployment/vpa-admission-controller`, wait 30s, re-check |
| `kubectl get crd \| grep autoscaling.k8s.io` is still empty after install | helm install silently failed | `helm -n kube-system status vpa` for the real error; usually a network timeout mid-`helm install` — re-run `install-vpa.sh` |
| Everything Running, but Lab 3's `kubectl describe vpa` shows no recommendation after 90s | recommender needs real usage history first | give it another 60-90s; the recommender polls metrics-server on an interval, it isn't instant |

## Cleanup (only if you want VPA removed entirely, not just the Lab 3 workload)

```bash
helm -n kube-system uninstall vpa
kubectl get crd | grep autoscaling.k8s.io   # should be empty again
rm -rf /tmp/autoscaler
```

Leave VPA installed if you're continuing to later days or the capstone —
[Stage 07](../../CAPSTONE/Stage07-HPA-Scaling/LAB-MANUAL.md) reuses it.
