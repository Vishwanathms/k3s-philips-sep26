# ex02 — verified run

Captured **2026-09-12** on k3s `v1.36.4+k3s1`, single node `lab-g2-vm2`,
namespace `d4-storage`. Result: **PASS** — the PVC bound to the
hand-created PV (not a provisioner), and `Retain` behaved differently from
ex01's `Delete` in exactly the documented way.

```console
$ kubectl apply -f ex02-static-pv-hostpath/pv.yaml
persistentvolume/manual-pv created
$ kubectl get pv manual-pv
NAME        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      STORAGECLASS
manual-pv   200Mi      RWO            Retain           Available   manual

$ kubectl apply -f ex02-static-pv-hostpath/pvc-and-pod.yaml
persistentvolumeclaim/manual-claim created
pod/manual-writer created

$ kubectl get pvc manual-claim -n d4-storage
NAME           STATUS   VOLUME      CAPACITY   ACCESS MODES   STORAGECLASS
manual-claim   Bound    manual-pv   200Mi      RWO            manual

$ kubectl exec manual-writer -n d4-storage -- cat /data/marker.txt
written-by-manual-writer
$ cat /mnt/d4-manual-pv/marker.txt      # on the node - same file
written-by-manual-writer
```

No provisioner is named `manual` — this PVC could only ever bind by matching
an existing PV with the same `storageClassName`, proving static and dynamic
provisioning are genuinely different mechanisms.

## `Retain` in action: deleting the PVC does NOT delete the data

```console
$ kubectl delete pod manual-writer -n d4-storage --now
$ kubectl delete pvc manual-claim -n d4-storage

$ kubectl get pv manual-pv
NAME        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM
manual-pv   200Mi      RWO            Retain           Released   d4-storage/manual-claim

$ cat /mnt/d4-manual-pv/marker.txt
written-by-manual-writer      # <- still there
```

**A `Released` PV is not automatically reusable.** A brand new PVC asking
for the same `storageClassName` stays `Pending`:

```console
$ kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: manual-claim-2, namespace: d4-storage }
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual
  resources: { requests: { storage: 100Mi } }
EOF
$ kubectl get pvc manual-claim-2 -n d4-storage
NAME             STATUS    VOLUME   STORAGECLASS   AGE
manual-claim-2   Pending            manual         3s

$ kubectl get pv manual-pv -o jsonpath='{.spec.claimRef}'
{"...","name":"manual-claim","namespace":"d4-storage",...}   # stale reference to the OLD claim
```

The fix is manual — clear the stale `claimRef`:

```console
$ kubectl delete pvc manual-claim-2 -n d4-storage
$ kubectl patch pv manual-pv --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
persistentvolume/manual-pv patched
$ kubectl get pv manual-pv
NAME        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS
manual-pv   200Mi      RWO            Retain           Available           manual
```

`Retain` trades convenience for safety: nothing is silently destroyed, but
every reclaim needs a human (or an operator) to confirm the data is safe to
reuse or wipe. Compare with ex01, where `local-path`'s `Delete` policy erased
both the PV object and its backing directory the moment the PVC was deleted.
