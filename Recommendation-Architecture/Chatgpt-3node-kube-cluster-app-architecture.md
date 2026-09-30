For a **3-node Kubernetes cluster** where you want to teach or demonstrate the **complete DevOps → DevSecOps → application deployment → observability → operations lifecycle**, I would not try to install dozens of CNCF Landscape tools. A curated stack of roughly **15–20 tools** gives you a far better platform.

The CNCF ecosystem itself shows this pattern: Kubernetes, Helm, Prometheus, cert-manager, Argo, Harbor, Cilium and related tools are among the more established production choices. :chatgpt-content-reference{index="0"}

## My recommended architecture

```text
                         DEVELOPER
                            │
                   ┌────────▼────────┐
                   │   GitHub/GitLab │
                   │ Source + PR/MR  │
                   └────────┬────────┘
                            │
                   ┌────────▼────────┐
                   │ Jenkins/GitLab  │
                   │      CI         │
                   └────────┬────────┘
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
         ▼                  ▼                  ▼
      SonarQube           Trivy             Maven/
      Code Scan       Image/FS Scan        npm/Python
         │                  │
         └──────────────────┼──────────────────┘
                            ▼
                     ┌─────────────┐
                     │   Harbor    │
                     │  Registry   │
                     └──────┬──────┘
                            │
                         IMAGE
                            │
                            ▼
                  ┌──────────────────┐
                  │     Argo CD      │
                  │      GitOps      │
                  └────────┬─────────┘
                           │
                           ▼
               ┌────────────────────────┐
               │ Kubernetes 3-node      │
               │                        │
               │ Node1  Node2  Node3    │
               │                        │
               │ Application Pods       │
               └──────────┬─────────────┘
                          │
          ┌───────────────┼────────────────┐
          │               │                │
          ▼               ▼                ▼
      Gateway API       Kyverno        cert-manager
       Traefik           Policy            TLS
          │
          ▼
       MetalLB
          │
          ▼
       USERS


              OBSERVABILITY
                    │
       ┌────────────┼────────────┐
       ▼            ▼            ▼
 Prometheus        Loki        Tempo
   Metrics         Logs        Traces
       │            │            │
       └────────────┼────────────┘
                    ▼
                 Grafana
```

# The stack I would build for your lab

| Layer | Recommended tool | Purpose | Priority |
|---|---|---|---|
| Kubernetes | **K3s** | Lightweight 3-node Kubernetes | ⭐⭐⭐⭐⭐ |
| Container runtime | **containerd** | Container runtime | Built-in |
| Package management | **Helm** | Kubernetes application packages | ⭐⭐⭐⭐⭐ |
| Source control | **GitHub / GitLab** | Source + manifests | ⭐⭐⭐⭐⭐ |
| CI | **Jenkins or GitLab CI** | Build/test pipelines | ⭐⭐⭐⭐⭐ |
| GitOps/CD | **Argo CD** | Kubernetes deployments | ⭐⭐⭐⭐⭐ |
| Registry | **Harbor** | Private OCI registry | ⭐⭐⭐⭐⭐ |
| Image scanning | **Trivy** | Vulnerability scanning | ⭐⭐⭐⭐⭐ |
| Code quality | **SonarQube** | SAST/code quality | ⭐⭐⭐⭐ |
| Secrets | **External Secrets Operator** | Secret integration | ⭐⭐⭐⭐ |
| TLS | **cert-manager** | Certificate automation | ⭐⭐⭐⭐⭐ |
| Networking | **Cilium** | CNI + NetworkPolicy + visibility | ⭐⭐⭐⭐ |
| LoadBalancer | **MetalLB** | Bare-metal LoadBalancer | ⭐⭐⭐⭐⭐ |
| North/South traffic | **Gateway API + Traefik** | Application routing | ⭐⭐⭐⭐⭐ |
| Policy | **Kyverno** | Kubernetes policy-as-code | ⭐⭐⭐⭐⭐ |
| Metrics | **Prometheus** | Metrics collection | ⭐⭐⭐⭐⭐ |
| Visualization | **Grafana** | Dashboards | ⭐⭐⭐⭐⭐ |
| Logging | **Loki** | Kubernetes logs | ⭐⭐⭐⭐⭐ |
| Tracing | **Tempo** | Distributed tracing | ⭐⭐⭐⭐ |
| Telemetry | **OpenTelemetry** | Metrics/logs/traces instrumentation | ⭐⭐⭐⭐⭐ |
| Backup | **Velero** | Kubernetes backup/restore | ⭐⭐⭐⭐⭐ |
| Autoscaling | **HPA + KEDA** | Application autoscaling | ⭐⭐⭐⭐ |
| Runtime Security | **Falco** | Runtime threat detection | ⭐⭐⭐⭐ |
| Developer portal | **Backstage** | Internal developer platform | ⭐⭐⭐ |
| Database operator | **CloudNativePG** | PostgreSQL on Kubernetes | ⭐⭐⭐⭐ |

OpenTelemetry is now a **CNCF Graduated** project, making it an especially strong choice for a modern observability curriculum. :chatgpt-content-reference{index="1"}

---

# 1. Kubernetes distribution

For **your training environment**, I'd continue with:

### K3s

```text
k3s-node01
    Server/control-plane
    Worker

k3s-node02
    Server/control-plane
    Worker

k3s-node03
    Server/control-plane
    Worker
```

Or for a more realistic workload architecture:

```text
Node-01
Control Plane + platform components

Node-02
Worker

Node-03
Worker
```

For training purposes, I'd prefer:

```text
3 Server nodes
+
all three schedulable
```

That lets students simulate HA while keeping hardware requirements reasonable.

---

# 2. Source control

Teach both:

```text
Git
   │
   ├── GitHub
   │
   └── GitLab
```

Repository design:

```text
application-source/
    src/
    Dockerfile
    Jenkinsfile

application-config/
    base/
    dev/
    staging/
    prod/

platform-gitops/
    argocd/
    monitoring/
    security/
    networking/
```

This separation becomes very important once you teach GitOps.

---

# 3. CI

You already train Jenkins, so I would keep:

### Jenkins

Pipeline:

```text
Developer
   │
   ▼
Git Push
   │
   ▼
Jenkins
   │
   ├─ Compile
   ├─ Unit Test
   ├─ SonarQube
   ├─ Build image
   ├─ Trivy scan
   └─ Push image
          │
          ▼
        Harbor
```

For another exercise, demonstrate:

```text
GitLab CI
```

But don't run Jenkins + GitLab runners + GitHub runners permanently on a small cluster.

Use Jenkins as the main teaching platform.

---

# 4. Container registry

## Harbor

This is one of the tools I strongly recommend adding to your platform.

```text
Jenkins
    │
docker build
    │
    ▼
  Trivy
    │
    ▼
  Harbor
    │
    ▼
 Kubernetes
```

Harbor gives students exposure to:

- Registry projects
- RBAC
- Image repositories
- Vulnerability scanning
- Retention
- Replication
- OCI artifacts
- Image signing concepts

Harbor is a CNCF Graduated project. :chatgpt-content-reference{index="2"}

---

# 5. Continuous deployment

## Argo CD

This should definitely be part of your platform.

Don't make Jenkins run:

```bash
kubectl apply
```

Instead:

```text
Jenkins
   │
   └── Update image version
            │
            ▼
       Git Manifest Repo
            │
            ▼
         Argo CD
            │
            ▼
       Kubernetes
```

That clearly demonstrates the difference between:

```text
CI                       CD

Jenkins                 Argo CD
────────                ────────

Build                   Sync
Test                    Deploy
Scan                    Detect drift
Image                   Self-heal
Push                    Rollback
```

Argo is CNCF Graduated and continues to see substantial production adoption. :chatgpt-content-reference{index="3"}

---

# 6. Application deployment

Teach three methods.

### Level 1

Plain YAML:

```text
Deployment
Service
ConfigMap
Secret
PVC
```

### Level 2

Helm:

```text
myapp/
├── Chart.yaml
├── values.yaml
└── templates/
```

### Level 3

Kustomize:

```text
base/
overlays/
   ├── dev
   ├── staging
   └── production
```

And then:

```text
Git
 ↓
Argo CD
 ↓
Kustomize / Helm
 ↓
Kubernetes
```

That gives students a very realistic workflow.

---

# 7. External traffic

I would change one thing in many traditional Kubernetes training courses.

Don't design new training mainly around:

```text
Ingress
+
Ingress-NGINX
```

Instead teach:

## Gateway API

Kubernetes is clearly moving toward Gateway API; Ingress-NGINX reached retirement in 2026, while Gateway API continues to mature with conformant implementations including Traefik, NGINX Gateway Fabric, HAProxy and others. :chatgpt-content-reference{index="4"}

Your stack could be:

```text
Internet
   │
   ▼
MetalLB
   │
   ▼
Traefik Gateway
   │
Gateway API
   │
HTTPRoute
   │
Service
   │
Pods
```

This would make your course much more current.

---

# 8. Certificates

## cert-manager

Architecture:

```text
Application
     │
Gateway
     │
cert-manager
     │
Let's Encrypt
     │
TLS Secret
```

Students should understand:

```yaml
Issuer
ClusterIssuer
Certificate
Secret
```

cert-manager is CNCF Graduated and widely adopted. :chatgpt-content-reference{index="5"}

---

# 9. Kubernetes security

This is where your platform can become a proper **DevSecOps lab**.

Use:

```text
Trivy
Kyverno
Falco
RBAC
NetworkPolicy
Secrets
Pod Security
```

## Trivy

Pipeline scanning:

```text
Source
 ↓
Docker build
 ↓
Trivy
 ↓
Harbor
```

Scan:

```text
Filesystem
Images
Kubernetes
IaC
SBOM
```

---

# 10. Policy engine

## Kyverno

I prefer Kyverno for your students over starting with OPA/Gatekeeper.

Why?

Policies look like Kubernetes resources.

Example requirements:

```text
✓ Containers must have CPU limits

✓ Containers cannot run privileged

✓ Images must come from Harbor

✓ Image tag :latest forbidden

✓ Pods must use non-root users

✓ Required labels

✓ Approved registries only
```

Flow:

```text
kubectl / ArgoCD
       │
       ▼
   API Server
       │
       ▼
    Kyverno
       │
   ┌───┴─────┐
   │         │
ALLOW      DENY
```

Kyverno reached CNCF Graduated status in March 2026. :chatgpt-content-reference{index="6"}

---

# 11. Runtime security

Add:

## Falco

Then your security becomes:

```text
Before deployment

Trivy
Kyverno
SonarQube

-----------------

After deployment

Falco
```

For example:

```text
Pod starts
   │
   ▼
Attacker executes shell
   │
   ▼
/bin/bash
   │
   ▼
Falco detects
   │
   ▼
Alert
```

Very useful for explaining the difference between:

```text
SAST
SCA
Image scanning
Admission security
Runtime security
```

---

# 12. Observability

This is an area where I'd upgrade your existing stack.

Instead of only:

```text
Prometheus
Grafana
Loki
```

build:

# LGTM + OpenTelemetry

```text
              Application
                  │
            OpenTelemetry
                  │
       ┌──────────┼───────────┐
       │          │           │
       ▼          ▼           ▼
   Prometheus    Loki       Tempo
    Metrics      Logs       Traces
       │          │           │
       └──────────┼───────────┘
                  ▼
               Grafana
```

Students then learn all three observability pillars:

```text
Metrics
Logs
Traces
```

instead of only monitoring.

---

# 13. Prometheus

Use:

```text
kube-prometheus-stack
```

You'll get:

```text
Prometheus
Alertmanager
Grafana
kube-state-metrics
node-exporter
Prometheus Operator
```

Monitor:

```text
Node CPU
Node RAM
Disk

Pod CPU
Pod Memory
Restarts

Deployments
DaemonSets
StatefulSets

API server
etcd

Application metrics
```

Prometheus remains one of the most widely adopted CNCF projects. :chatgpt-content-reference{index="7"}

---

# 14. Logs

## Loki

Flow:

```text
Container stdout
        │
        ▼
Grafana Alloy
        │
        ▼
       Loki
        │
        ▼
     Grafana
```

For a new build, I'd actually teach **Grafana Alloy** as the collector rather than focusing only on older Promtail deployments.

---

# 15. Distributed tracing

## Tempo + OpenTelemetry

Student application:

```text
Frontend
    │
    ▼
Backend
    │
    ▼
Redis
    │
    ▼
PostgreSQL
```

Tempo lets students see:

```text
Frontend
   12 ms
     ↓
Backend
   44 ms
     ↓
Database
   184 ms
```

This makes microservice troubleshooting much easier to demonstrate.

---

# 16. Networking

For basic K3s:

```text
Flannel
```

is perfectly fine.

But for an advanced module I'd install:

## Cilium

because then you can demonstrate:

```text
CNI
NetworkPolicy
eBPF
Network visibility
Service connectivity
Security
Hubble
```

Architecture:

```text
Pod A
  │
Cilium
  │
eBPF
  │
Cilium
  │
Pod B
```

Add:

```text
Hubble
```

for visualization.

Cilium is also among CNCF's established cloud-native networking projects. :chatgpt-content-reference{index="8"}

---

# 17. Secrets

Start students with:

```text
Kubernetes Secret
```

then explain why that's insufficient for serious environments.

Move to:

## External Secrets Operator

Architecture:

```text
Vault
  │
  │
External Secrets
Operator
  │
  ▼
Kubernetes Secret
  │
  ▼
Application
```

For your lab:

## HashiCorp Vault + External Secrets Operator

would be excellent.

Then students learn real enterprise secrets management.

---

# 18. Persistent storage

For your basic 3-node K3s:

```text
local-path-provisioner
```

is okay.

For a storage lab:

```text
Longhorn
```

is an excellent choice.

Architecture:

```text
         PVC
          │
          ▼
      Longhorn
          │
 ┌────────┼────────┐
 ▼        ▼        ▼
Node1    Node2    Node3
Disk     Disk     Disk
```

This lets you demonstrate replica storage and node failures.

---

# 19. Stateful applications

I would include:

## CloudNativePG

instead of simply deploying PostgreSQL with a Deployment.

```text
CloudNativePG Operator
         │
         ▼
 PostgreSQL Cluster

 PG-1 Primary

 PG-2 Replica

 PG-3 Replica
```

This lets students understand:

```text
Kubernetes Operators
CRDs
Failover
Replication
Backups
Stateful workloads
```

---

# 20. Backup

## Velero

Very important.

Teach:

```text
Cluster
  │
Velero
  │
  ▼
MinIO / S3
```

Backup:

```text
Namespace
Deployments
Services
Secrets
ConfigMaps
CRDs
PVC metadata
```

Then simulate:

```bash
kubectl delete namespace production
```

and restore it.

This is one of the most effective Kubernetes recovery labs.

---

# 21. Autoscaling

Teach these progressively:

```text
HPA
 │
 ▼
CPU / Memory

VPA
 │
 ▼
Resource sizing

KEDA
 │
 ▼
Event-driven scaling
```

Example:

```text
RabbitMQ Queue
      │
      ▼
     KEDA
      │
      ▼
Deployment

2 pods
 ↓
20 pods
```

---

# 22. Platform engineering

Only add this after students understand Kubernetes:

## Backstage

Architecture:

```text
                   Backstage
                      │
        ┌─────────────┼──────────────┐
        │             │              │
        ▼             ▼              ▼
      GitHub        ArgoCD         Grafana
        │
        ▼
  Service Template
        │
        ▼
New Microservice
```

You can then teach:

```text
Developer portal
Service catalogue
Golden paths
Templates
Self-service infrastructure
```

This would fit very nicely with the **platform engineering / IDP** section you've already been developing for your Kubernetes training.

---

# The final stack I recommend for you

I would make your environment:

```text
             VISHWACLOUDLAB
        Kubernetes DevSecOps Platform

------------------------------------------------

DEVELOPMENT

Git
GitHub / GitLab
Maven / Python / npm

------------------------------------------------

CI

Jenkins
SonarQube
Trivy

------------------------------------------------

ARTIFACT MANAGEMENT

Harbor

------------------------------------------------

GITOPS

Argo CD
Helm
Kustomize

------------------------------------------------

KUBERNETES

K3s
containerd

Node-01
Node-02
Node-03

------------------------------------------------

NETWORKING

Cilium
Hubble
MetalLB
Traefik
Gateway API

------------------------------------------------

SECURITY

RBAC
NetworkPolicy
Pod Security
Kyverno
Falco
Trivy

------------------------------------------------

SECRETS

Vault
External Secrets Operator

------------------------------------------------

TLS

cert-manager

------------------------------------------------

OBSERVABILITY

OpenTelemetry
Prometheus
Grafana
Loki
Tempo
Alertmanager

------------------------------------------------

STORAGE

Longhorn

------------------------------------------------

DATABASE

CloudNativePG
Redis

------------------------------------------------

BACKUP

Velero
MinIO

------------------------------------------------

SCALING

HPA
VPA
KEDA

------------------------------------------------

PLATFORM ENGINEERING

Backstage
```

That is a **very strong end-to-end Kubernetes training platform**.

## And the complete student flow becomes

```text
1. Developer writes code
              ↓
2. Git push
              ↓
3. Jenkins pipeline
              ↓
4. Unit testing
              ↓
5. SonarQube
              ↓
6. Docker build
              ↓
7. Trivy scan
              ↓
8. Push image → Harbor
              ↓
9. Update GitOps repo
              ↓
10. Argo CD detects change
              ↓
11. Kyverno validates deployment
              ↓
12. Application deployed
              ↓
13. Gateway API exposes app
              ↓
14. cert-manager provides TLS
              ↓
15. Cilium controls networking
              ↓
16. External Secrets injects secrets
              ↓
17. Prometheus collects metrics
              ↓
18. Loki collects logs
              ↓
19. Tempo stores traces
              ↓
20. Grafana visualizes everything
              ↓
21. Falco monitors runtime
              ↓
22. KEDA/HPA scales workload
              ↓
23. Velero protects workload
```

This would also be a strong **capstone architecture for your DevSecOps course**, because students aren't learning isolated tools—they can follow **one application from code all the way through CI, security, GitOps, production deployment, monitoring, incident detection and disaster recovery**. :chatgpt-content-reference{index="9"}

One important recommendation: **don't install everything into the 3-node cluster immediately.** Build it in roughly four stages: **Core Kubernetes → CI/CD → Security → Observability/Operations**. That keeps the cluster understandable and avoids turning the lab into a resource-heavy tool museum.