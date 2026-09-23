#!/usr/bin/env bash
# ex07 — create the real Kubernetes user "alice" (x509 client cert) and a
# standalone kubeconfig for her, via the CertificateSigningRequest API.
#
# Requires a kubeconfig with cluster-admin (to approve the CSR). Run from
# this script's parent directory (ex07-rbac-user-pod-access/), or it will
# cd there itself.
#
# Everything this script creates lives under alice-identity/, which is
# git-ignored: it is a per-run private key + client certificate and must
# never be committed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

CN="alice"
O="developers"
OUTDIR="alice-identity"
mkdir -p "$OUTDIR"

echo "==> Generating private key + CSR for CN=${CN}"
openssl genrsa -out "$OUTDIR/alice.key" 2048 2>/dev/null
openssl req -new -key "$OUTDIR/alice.key" -out "$OUTDIR/alice.csr" \
  -subj "/CN=${CN}/O=${O}"

echo "==> Submitting CertificateSigningRequest/alice-csr"
CSR_B64=$(base64 -w0 "$OUTDIR/alice.csr")
cat > "$OUTDIR/csr-alice.yaml" <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: alice-csr
spec:
  request: ${CSR_B64}
  signerName: kubernetes.io/kube-apiserver-client
  usages:
    - client auth
EOF
kubectl apply -f "$OUTDIR/csr-alice.yaml"

echo "==> Approving alice-csr (requires cluster-admin)"
kubectl certificate approve alice-csr

echo "==> Waiting for the signed certificate"
for i in $(seq 1 10); do
  CERT=$(kubectl get csr alice-csr -o jsonpath='{.status.certificate}')
  [ -n "$CERT" ] && break
  sleep 1
done
if [ -z "$CERT" ]; then
  echo "ERROR: certificate was not issued (check the CSR condition)" >&2
  kubectl get csr alice-csr
  exit 1
fi
echo "$CERT" | base64 -d > "$OUTDIR/alice.crt"
openssl x509 -in "$OUTDIR/alice.crt" -noout -subject -issuer -dates

echo "==> Building alice.kubeconfig"
SERVER=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
  | base64 -d > "$OUTDIR/ca.crt"

KCFG="$OUTDIR/alice.kubeconfig"
kubectl --kubeconfig="$KCFG" config set-cluster k3s-lab \
  --server="$SERVER" --certificate-authority="$OUTDIR/ca.crt" --embed-certs=true
kubectl --kubeconfig="$KCFG" config set-credentials alice \
  --client-certificate="$OUTDIR/alice.crt" --client-key="$OUTDIR/alice.key" --embed-certs=true
kubectl --kubeconfig="$KCFG" config set-context alice@k3s-lab \
  --cluster=k3s-lab --user=alice
kubectl --kubeconfig="$KCFG" config use-context alice@k3s-lab

echo "==> Done. Use it with:"
echo "    kubectl --kubeconfig=${OUTDIR}/alice.kubeconfig <command>"
echo "    export KUBECONFIG=$(pwd)/${OUTDIR}/alice.kubeconfig   # or switch entirely"
