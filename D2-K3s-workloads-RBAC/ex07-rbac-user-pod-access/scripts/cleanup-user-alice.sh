#!/usr/bin/env bash
# ex07 — remove the CertificateSigningRequest and the locally generated
# key/cert/kubeconfig for "alice". Does NOT touch the RBAC objects or the
# namespace; use `kubectl delete -f .` / `kubectl delete namespace` for that.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

kubectl delete csr alice-csr --ignore-not-found
rm -rf alice-identity
echo "==> Removed CSR/alice-csr and alice-identity/"
