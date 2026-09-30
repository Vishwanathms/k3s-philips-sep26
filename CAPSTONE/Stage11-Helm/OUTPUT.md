# Capstone stage 11 — verified run

Captured **2026-09-29** on k3s `v1.36.4+k3s1`, Helm `v3.21.3`, over a
healthy, running Stage 10 (6 Pods, all `2/2`). Scope: package into one
chart, real upgrade, real `--atomic` failure + rollback, manual rollback.
No GitLab push, no Harbor, no image rebuild — deferred, per scope. Counter
climbed from 115663 (before `helm install`) to 115847 (end) — loadgen ran
throughout; nothing was ever paused or restarted except the Pods each step
deliberately changed. Result: **PASS** for H1–H5.

> `helm template` + `kubectl diff` against the live cluster showed **zero
> diff** before any adoption — proof the chart is a faithful conversion of
> Stage 10's manifests, not a rewrite.

## Before: chart matches the live cluster exactly

```console
$ helm lint chart/capstone
==> Linting capstone
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed

$ helm template capstone chart/capstone -n capstone > /tmp/rendered.yaml
$ kubectl apply --dry-run=server -f /tmp/rendered.yaml | grep -v unchanged
poddisruptionbudget.policy/web configured (server dry run)
poddisruptionbudget.policy/api configured (server dry run)
statefulset.apps/redis configured (server dry run)

$ kubectl diff -f /tmp/rendered.yaml; echo "exit=$?"
exit=0
```

`kubectl diff` (a real field-by-field comparison) found nothing — the
"configured" lines above were `dry-run=server`'s own noise, not an actual
difference.

## H1 — install refused

```console
$ helm install capstone chart/capstone -n capstone --dry-run
Error: INSTALLATION FAILED: Unable to continue with install: PriorityClass "capstone-data" in namespace "" exists and cannot be imported into the current release: invalid ownership metadata; label validation error: missing key "app.kubernetes.io/managed-by": must be set to "Helm"; annotation validation error: missing key "meta.helm.sh/release-name": must be set to "capstone"; annotation validation error: missing key "meta.helm.sh/release-namespace": must be set to "capstone"
```

## H2 — adoption, then install

```console
$ kubectl -n capstone get pods -o custom-columns='NAME:...,RESTARTS:...,AGE:...'
api-6d655c4644-4wrvq      0   2026-09-29T09:17:46Z
api-6d655c4644-g2gng      0   2026-09-29T09:18:18Z
loadgen-749dfcb48-fdllm   0   2026-09-29T09:17:58Z
redis-0                   0   2026-09-29T11:56:09Z
web-5567498448-2bcgz      0   2026-09-29T09:18:04Z
web-5567498448-grcjl      0   2026-09-29T09:17:48Z

$ ./scripts/adopt-into-helm.sh
[cluster-scoped]
priorityclass.scheduling.k8s.io/capstone-data labeled
...
[namespace] ... [namespaced objects in capstone] ...
Done. Every object the chart manages now carries Helm's ownership metadata.

$ helm install capstone chart/capstone -n capstone
NAME: capstone
LAST DEPLOYED: Tue Sep 29 18:10:00 2026
NAMESPACE: capstone
STATUS: deployed
REVISION: 1

$ kubectl -n capstone get pods -o custom-columns='NAME:...,RESTARTS:...,AGE:...'
api-6d655c4644-4wrvq      0   2026-09-29T09:17:46Z
api-6d655c4644-g2gng      0   2026-09-29T09:18:18Z
loadgen-749dfcb48-fdllm   0   2026-09-29T09:17:58Z
redis-0                   0   2026-09-29T11:56:09Z
web-5567498448-2bcgz      0   2026-09-29T09:18:04Z
web-5567498448-grcjl      0   2026-09-29T09:17:48Z
```

Byte-for-byte identical to before — `diff` on the two listings is empty.

```console
$ helm list -n capstone
NAME      NAMESPACE  REVISION  STATUS    CHART           APP VERSION
capstone  capstone   1         deployed  capstone-1.0.0  1.0.0

$ curl -s -H 'Host: capstone.k3s.local' http://192.168.230.103/api/hits
{"hits":115663,"pod":"api-6d655c4644-4wrvq","version":"1.0.0"}
```

## H3 — upgrade: web to 3 replicas

```console
$ helm upgrade capstone chart/capstone -n capstone --set web.replicaCount=3
Release "capstone" has been upgraded. Happy Helming!
REVISION: 2

$ kubectl -n capstone rollout status deploy/web --timeout=60s
Waiting for deployment "web" rollout to finish: 2 of 3 updated replicas are available...
deployment "web" successfully rolled out

$ kubectl -n capstone get pods -l app=web
web-5567498448-2bcgz   2/2   Running   0   3h22m
web-5567498448-5mxhs   2/2   Running   0   16s
web-5567498448-grcjl   2/2   Running   0   3h22m
```

The two original web Pods keep their age; only a third was added.

## H4 — `--atomic` catches a bad upgrade

```console
$ helm upgrade capstone chart/capstone -n capstone \
    --set web.replicaCount=3 --set api.image.tag=9.9.9-missing --atomic --timeout=45s
Error: UPGRADE FAILED: release capstone failed, and has been rolled back due to atomic being set: context deadline exceeded

$ helm history capstone -n capstone
REVISION  UPDATED                   STATUS      DESCRIPTION
1         Tue Sep 29 18:10:00 2026  superseded  Install complete
2         Tue Sep 29 18:10:23 2026  superseded  Upgrade complete
3         Tue Sep 29 18:10:55 2026  failed      Upgrade "capstone" failed: context deadline exceeded
4         Tue Sep 29 18:11:48 2026  deployed    Rollback to 2

$ kubectl -n capstone get pods -l app=api
api-6d655c4644-4wrvq   2/2   Running   0   3h24m
api-6d655c4644-g2gng   2/2   Running   0   3h23m
$ kubectl -n capstone get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
localhost:5000/capstone-api:1.0.0
$ curl -s -H 'Host: capstone.k3s.local' http://192.168.230.103/api/hits
{"hits":115810,"pod":"api-6d655c4644-4wrvq","version":"1.0.0"}
```

api Pods were never touched — the good `web.replicaCount=3` half of the
upgrade never got the chance to apply either, because Helm rolled the
**whole release** back to revision 2's state, not just the broken image.

## H5 — manual rollback, and a rollback that can't succeed

```console
$ helm rollback capstone 1 -n capstone
Rollback was a success! Happy Helming!
$ kubectl -n capstone rollout status deploy/web --timeout=60s
deployment "web" successfully rolled out
$ kubectl -n capstone get pods -l app=web
web-5567498448-2bcgz   2/2   Running   0   3h24m
web-5567498448-grcjl   2/2   Running   0   3h24m

$ helm history capstone -n capstone
REVISION  UPDATED                   STATUS      DESCRIPTION
1         Tue Sep 29 18:10:00 2026  superseded  Install complete
2         Tue Sep 29 18:10:23 2026  superseded  Upgrade complete
3         Tue Sep 29 18:10:55 2026  failed      Upgrade "capstone" failed: context deadline exceeded
4         Tue Sep 29 18:11:48 2026  superseded  Rollback to 2
5         Tue Sep 29 18:12:12 2026  deployed    Rollback to 1

$ helm rollback capstone 99 -n capstone
Error: release has no 99 version
```

## Final state

```console
$ kubectl -n capstone get pods
api-6d655c4644-4wrvq      2/2   Running   0   3h24m
api-6d655c4644-g2gng      2/2   Running   0   3h24m
loadgen-749dfcb48-fdllm   2/2   Running   0   3h24m
redis-0                   2/2   Running   0   46m
web-5567498448-2bcgz      2/2   Running   0   3h24m
web-5567498448-grcjl      2/2   Running   0   3h24m
$ curl -s -H 'Host: capstone.k3s.local' http://192.168.230.103/api/hits
{"hits":115847,"pod":"api-6d655c4644-g2gng","version":"1.0.0"}
```

(`redis-0`'s 46m age is from Stage 10's OOM drill, unrelated to this stage.)
A fresh backup was taken afterward at `~/capstone-backups/post-stage11`.
