#!/usr/bin/env bash
# One-time migration: the capstone app has been running since Stage 02 via
# plain `kubectl apply -f manifests/`. Helm refuses to install over objects
# it doesn't already own:
#
#   Error: INSTALLATION FAILED: Unable to continue with install:
#   PriorityClass "capstone-data" ... exists and cannot be imported into
#   the current release: invalid ownership metadata; label validation
#   error: missing key "app.kubernetes.io/managed-by": must be set to
#   "Helm"; annotation validation error: missing key
#   "meta.helm.sh/release-name": must be set to "capstone" ...
#
# Helm 3 will "adopt" an existing object instead of erroring IF it already
# carries these exact label + 2 annotations. This script adds them to every
# object the chart manages, changing NOTHING else - no object is deleted or
# recreated, so the running app (and the hit counter) is never touched.
#
# Safe to re-run. Run once, before the first `helm install` in the manual.
set -euo pipefail
NS=capstone
RELEASE=capstone

label_and_annotate() {
  local kind="$1" name="$2" ns_flag=()
  [ -n "${3:-}" ] && ns_flag=(-n "$3")
  kubectl "${ns_flag[@]}" label   "$kind" "$name" app.kubernetes.io/managed-by=Helm --overwrite
  kubectl "${ns_flag[@]}" annotate "$kind" "$name" \
    meta.helm.sh/release-name="$RELEASE" \
    meta.helm.sh/release-namespace="$NS" --overwrite
}

echo "[cluster-scoped]"
for pc in capstone-data capstone-app capstone-batch; do
  label_and_annotate priorityclass "$pc"
done

echo "[namespace]"
label_and_annotate namespace "$NS"

echo "[namespaced objects in $NS]"
label_and_annotate limitrange        capstone-defaults "$NS"
label_and_annotate resourcequota     capstone-quota     "$NS"
for sa in web api redis loadgen; do
  label_and_annotate serviceaccount "$sa" "$NS"
done
label_and_annotate service           redis "$NS"
label_and_annotate statefulset       redis "$NS"
label_and_annotate deployment        api   "$NS"
label_and_annotate service           api   "$NS"
label_and_annotate deployment        web   "$NS"
label_and_annotate service           web   "$NS"
label_and_annotate ingress           capstone "$NS"
label_and_annotate poddisruptionbudget web "$NS"
label_and_annotate poddisruptionbudget api "$NS"
label_and_annotate horizontalpodautoscaler api "$NS"
label_and_annotate verticalpodautoscaler web   "$NS"
label_and_annotate verticalpodautoscaler redis "$NS"
label_and_annotate deployment        loadgen "$NS"
for np in default-deny allow-dns-and-linkerd web api redis loadgen; do
  label_and_annotate networkpolicy "$np" "$NS"
done

echo
echo "Done. Every object the chart manages now carries Helm's ownership"
echo "metadata. Next: helm install $RELEASE ../chart/capstone -n $NS"
