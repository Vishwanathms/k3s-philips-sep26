# ---------------------------------------------------------
# 1. Namespace
# ---------------------------------------------------------
apiVersion: v1
kind: Namespace
metadata:
  name: day11-security

---
# ---------------------------------------------------------
# 2. ServiceAccount
# Identity that our application Pod will use
# ---------------------------------------------------------
apiVersion: v1
kind: ServiceAccount
metadata:
  name: security-app-sa
  namespace: day11-security

---
# ---------------------------------------------------------
# 3. Role
# Defines WHAT the ServiceAccount is allowed to do
# ---------------------------------------------------------
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: security-app-role
  namespace: day11-security

rules:

  # ---- Read Secrets -------------------------------------
  - apiGroups: [""]
    resources: ["secrets"]
    verbs:
      - get
      - list

  # ---- Read Pods ----------------------------------------
  - apiGroups: [""]
    resources: ["pods"]
    verbs:
      - get
      - list
      - watch

  # ---- Read + Write NetworkPolicies ---------------------
  - apiGroups: ["networking.k8s.io"]
    resources: ["networkpolicies"]
    verbs:
      - get
      - list
      - create
      - update
      - patch

---
# ---------------------------------------------------------
# 4. RoleBinding
# Connects ServiceAccount → Role
# ---------------------------------------------------------
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: security-app-binding
  namespace: day11-security

subjects:
  - kind: ServiceAccount
    name: security-app-sa
    namespace: day11-security

roleRef:
  kind: Role
  name: security-app-role
  apiGroup: rbac.authorization.k8s.io

---
# ---------------------------------------------------------
# 5. Pod
# Uses the ServiceAccount
# ---------------------------------------------------------
apiVersion: v1
kind: Pod
metadata:
  name: security-app
  namespace: day11-security
spec:

  serviceAccountName: security-app-sa

  containers:
    - name: app
      image: bitnami/kubectl:latest
      command: ["sleep", "3600"]