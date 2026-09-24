# Day 02 — Assignment

Assignment covering Day 01 and Day 02 material only: Kubernetes workloads, configuration (ConfigMap/Secret), and RBAC on k3s.

| File | Purpose |
|---|---|
| [ASSIGNMENT.md](ASSIGNMENT.md) | The student brief — scope, scenario, tasks, self-check, checklist. **Start here.** |
| [broken/](broken/) | Three pre-broken RBAC manifests used in Part D. Each header comment carries the support ticket. |
| `.gitignore` | Blocks the credential material Part C generates from being committed. |

**Level:** intermediate → advanced · **4–6 hours**

## Shape of it

One scenario (the *Acme Imaging* platform — two app teams, SRE on-call, a CI pipeline, and an external auditor) runs through all five parts, so the RBAC in Part C locks down the workloads built in Part A rather than being an unrelated exercise.

| Part | Topic | Built from |
|---|---|---|
| A | Workloads — ReplicaSet self-healing, Deployment rollout/rollback, StatefulSet ordering, DaemonSet, Job/CronJob, init + sidecar + lifecycle hooks + shutdown sequence | `PPT1-Kubernetes_Workloads.pdf`, D1 ex01/ex02 |
| B | Configuration — env var → ConfigMap (two consumption methods) → Secret | ex03, ex04, ex05 |
| C | RBAC — CI ServiceAccount, x509 human user, reusable ClusterRole, privilege-escalation review | ex06, ex07, the real-world RBAC reference |
| D | RBAC troubleshooting — diagnose and minimally fix the three `broken/` manifests | the troubleshooting reference |
| E | Write-up | — |

Part A follows the deck's own hands-on lab sequence (ReplicaSet → Deployment rollout → StatefulSet → Jobs/CronJobs → init & sidecar → lifecycle & shutdown), so nothing in it requires material the students haven't seen.

Part D's defects are three failure modes straight from the [troubleshooting reference](../ex06-rbac-serviceaccount/REAL_WORLD_RBAC_AND_TROUBLESHOOTING.md): a missing `deployments/scale` subresource, a missing `pods/log` subresource, and a RoleBinding that matches nothing (wrong `roleRef` namespace *and* wrong subject namespace).

## Scope boundary

The brief opens with an explicit **out of scope** list — Service types and headless Services, DNS internals, Ingress, PV/PVC/StorageClasses, resource requests/limits and quotas, scheduling, autoscaling, Helm — because several of these are name-checked on the workloads slides as forward references. In particular:

- **A3 (StatefulSet)** asks for ordered creation/termination and stable Pod identity, using `emptyDir`. It does **not** ask for `volumeClaimTemplates` or a headless Service, though the slide mentions both.
- **A4 (DaemonSet)** asks about the `DESIRED` count coming from node count. It does **not** ask for `nodeSelector` or tolerations.
- **A6** uses a `readinessProbe` only in the context of the startup/shutdown sequence taught on the deck, not as a probe-tuning exercise.
- Services appear only as plumbing, exactly as in D1 ex02.

## Notes for instructors

- The assignment pushes students to **prove the boundary** of each permission rather than just make commands succeed — every RBAC task asks for a passing *and* a failing `auth can-i`.
- `broken/task-d3.yaml` carries **two** independent defects; students are told the count but not the locations.
- Part C2 asks for a real kubeconfig authenticating as the user. `--as` impersonation will appear to work but skips the authentication half of the lesson, so it's worth checking for.
- The `imagePullSecrets` extension in Part B needs a Docker Hub account, so it's optional.
- No answer key is included. If you want one for the Part D defects to hand to co-instructors, it can be added as a separate file that isn't distributed with the brief.
