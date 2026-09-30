For a **single-node K3s lab**, I would simplify the stack significantly. The goal should be to preserve the **complete DevOps → DevSecOps → deployment → observability flow**, but avoid tools that are too heavy or that only make sense for HA/multi-node clusters.

## Recommended single-node K3s architecture

```text
                    DEVELOPER
                        │
                 GitHub / GitLab
                        │
                        ▼
                     Jenkins
                        │
        ┌───────────────┼────────────────┐
        ▼               ▼                ▼
     Maven/npm       SonarQube         Trivy
        │                                 │
        └────────────────┬────────────────┘
                         ▼
                       Harbor
                         │
                         ▼
                      Argo CD
                         │
                         ▼
                ┌─────────────────┐
                │ Single-node K3s │
                │                 │
                │ Applications    │
                │ Services        │
                │ Databases       │
                └────────┬────────┘
                         │
                  Traefik / Gateway
                         │
                         ▼
                       USER

      ┌──────────────── OBSERVABILITY ────────────────┐
      │                                               │
      ▼                      ▼                        ▼
 Prometheus                Loki                    Tempo
      │                      │                        │
      └──────────────────────┼────────────────────────┘
                             ▼
                          Grafana
```

## The stack I recommend

| Layer | Tool | Recommendation |
|---|---|---|
| Kubernetes | **K3s** | Must have |
| Runtime | **containerd** | Already included |
| Package manager | **Helm** | Must have |
| Source control | **GitHub / GitLab** | Must have |
| CI | **Jenkins** | Must have |
| Code quality | **SonarQube** | Useful |
| Image scan | **Trivy** | Must have |
| Registry | **Harbor** | Recommended, but can be external |
| GitOps/CD | **Argo CD** | Must have |
| Ingress/Gateway | **Traefik** | Built into K3s |
| Load balancing | **Not required** | Single node |
| TLS | **cert-manager** | Recommended |
| Policy | **Kyverno** | Recommended |
| Runtime security | **Falco** | Optional |
| Metrics | **Prometheus** | Must have |
| Dashboard | **Grafana** | Must have |
| Logs | **Loki** | Recommended |
| Traces | **Tempo** | Optional |
| Telemetry | **OpenTelemetry** | Recommended for advanced labs |
| Storage | **local-path provisioner** | Enough for lab |
| Backup | **Velero + MinIO/S3** | Recommended |
| Scaling | **HPA** | Good for demo |
| Event scaling | **KEDA** | Optional |
| Secrets | **Kubernetes Secrets → Vault/ESO** | Progressive learning |

# What I would NOT install on the single node initially

A few tools from the 3-node design are unnecessary or too heavy.

```text
Cilium
Longhorn
CloudNativePG HA
MetalLB
Backstage
Multiple Grafana stack components
Large GitLab server
Vault HA
```

They can still be demonstrated later, but I wouldn't make them part of the baseline.

## Why?

Because a single-node cluster cannot really demonstrate:

```text
Node failover
Storage replication
Control-plane HA
Worker HA
Pod rescheduling across nodes
Multi-node networking
Cluster autoscaling
Database replica failover
```

So there is little value in consuming resources just to install tools designed around those capabilities.

# Networking

K3s already gives you a very good simple stack:

```text
Application Pod
      │
      ▼
   Service
      │
      ▼
   Traefik
      │
      ▼
Node IP : 80/443
      │
      ▼
     User
```

For your single-node course, this is sufficient.

You can demonstrate:

```text
ClusterIP
NodePort
Ingress
Gateway API
```

You don't need MetalLB unless you specifically want to teach `LoadBalancer` service behavior on bare metal.

# CI/CD flow

I'd use this exact workflow:

```text
Developer
   │
   ▼
GitHub
   │
   ▼
Jenkins
   │
   ├── Build
   ├── Unit Test
   ├── SonarQube
   ├── Trivy FS scan
   ├── Docker build
   └── Trivy image scan
          │
          ▼
        Harbor
          │
          ▼
    GitOps repository
          │
          ▼
        Argo CD
          │
          ▼
          K3s
```

This is almost identical to the production architecture, which is excellent for students.

# Application deployment

Use three levels.

### Beginner

```text
Deployment
Service
ConfigMap
Secret
PVC
Ingress
```

### Intermediate

```text
Helm
```

### Advanced

```text
Kustomize
+
Argo CD
```

Example:

```text
app-config/
├── base
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
│
└── overlays
    ├── dev
    └── prod
```

Even though there is only one physical cluster, you can simulate environments using namespaces:

```text
dev
test
staging
prod
```

That is very useful for training.

# Security stack

I would use:

```text
                    APPLICATION
                         │
               ┌─────────┴──────────┐
               │                    │
              CI               Kubernetes
               │                    │
       ┌───────┼───────┐       ┌───┼────────┐
       ▼       ▼       ▼       ▼   ▼        ▼
 SonarQube   Trivy   SBOM     RBAC Kyverno NetworkPolicy
                                         │
                                         ▼
                                       Falco
```

Students then learn the stages clearly.

### Before deployment

```text
SonarQube
Trivy
SBOM
```

### During admission

```text
Kyverno
Pod Security
RBAC
NetworkPolicy
```

### Runtime

```text
Falco
```

# Secrets

Start simple:

```yaml
apiVersion: v1
kind: Secret
```

Then demonstrate:

```text
Application
    │
    ▼
Kubernetes Secret
```

Later move to:

```text
Vault
   │
External Secrets Operator
   │
Kubernetes Secret
   │
Application
```

For single-node labs, I would run Vault separately or only enable it during the relevant module rather than leaving it permanently running.

# Monitoring

I'd definitely install:

```text
kube-prometheus-stack
```

which provides most of what you need:

```text
Prometheus
Grafana
Alertmanager
kube-state-metrics
node-exporter
```

Then students can monitor:

```text
Node CPU
Node RAM
Disk
Pods
Deployments
Container CPU
Container memory
Pod restarts
Kubernetes API
Application metrics
```

# Logging

Add:

```text
Grafana Alloy
      │
      ▼
     Loki
      │
      ▼
   Grafana
```

Then you can correlate:

```text
Namespace
Pod
Container
Application
Error
```

# Tracing

Tempo is useful but not mandatory for your basic stack.

For an advanced microservices lab:

```text
Frontend
   │
   ▼
Backend API
   │
   ▼
Redis/Postgres
```

with:

```text
OpenTelemetry
      │
      ▼
    Tempo
      │
      ▼
   Grafana
```

This gives students:

```text
Metrics  → Prometheus
Logs     → Loki
Traces   → Tempo
```

which is excellent for showing real observability.

# Storage

For the single node, keep:

```text
K3s local-path-provisioner
```

Architecture:

```text
Pod
 │
PVC
 │
StorageClass
 │
local-path
 │
Node Disk
```

This is more than enough.

I wouldn't use Longhorn by default because:

```text
1 node
=
No true storage HA
```

Longhorn makes much more sense when you move students to 3 nodes.

# Database

For beginner labs:

```text
PostgreSQL
Redis
MySQL
MongoDB
```

can simply be deployed with:

```text
StatefulSet
+
PVC
+
Headless Service
```

For example:

```text
Backend
   │
   ▼
redis-service
   │
   ▼
redis-0
   │
   ▼
PVC
```

That is actually more useful educationally than hiding everything behind an operator immediately.

# Backup

Keep Velero.

```text
K3s
 │
Velero
 │
 ├── Kubernetes objects
 │
 └── PVC backup
       │
       ▼
    MinIO / S3
```

Then run an excellent lab:

```text
Create application
        ↓
Create data
        ↓
Velero backup
        ↓
Delete namespace
        ↓
Restore
        ↓
Verify application
```

# Autoscaling

You can absolutely demonstrate HPA on one node.

```text
Load Generator
       │
       ▼
Application
       │
       ▼
CPU increases
       │
       ▼
Metrics Server
       │
       ▼
HPA
       │
       ▼
1 Pod → 3 Pods → 5 Pods
```

The important teaching point is:

> HPA scales pods, not machines.

On a single node:

```text
Pods scale
    ↓
Node eventually has no capacity
    ↓
Additional Pods become Pending
```

This is actually a very useful demonstration.

# My recommended single-node VishwaCloudLab stack

```text
        SINGLE-NODE K3S DEVSECOPS LAB
================================================

SOURCE CONTROL
Git
GitHub / GitLab

------------------------------------------------

BUILD
Maven
npm
Python

------------------------------------------------

CI
Jenkins

------------------------------------------------

CODE QUALITY
SonarQube

------------------------------------------------

SECURITY SCANNING
Trivy

------------------------------------------------

REGISTRY
Harbor

------------------------------------------------

GITOPS
Argo CD

------------------------------------------------

DEPLOYMENT
YAML
Helm
Kustomize

------------------------------------------------

KUBERNETES
K3s
containerd

------------------------------------------------

NETWORKING
Flannel
CoreDNS
Traefik

------------------------------------------------

TRAFFIC
Ingress
Gateway API

------------------------------------------------

TLS
cert-manager

------------------------------------------------

SECURITY
RBAC
ServiceAccount
NetworkPolicy
Pod Security
Kyverno

------------------------------------------------

RUNTIME SECURITY
Falco

------------------------------------------------

SECRETS
Kubernetes Secrets
External Secrets
Vault - advanced lab

------------------------------------------------

OBSERVABILITY
Prometheus
Grafana
Alertmanager

------------------------------------------------

LOGGING
Grafana Alloy
Loki

------------------------------------------------

TRACING
OpenTelemetry
Tempo - advanced lab

------------------------------------------------

STORAGE
local-path-provisioner

------------------------------------------------

DATABASES
PostgreSQL
Redis

------------------------------------------------

BACKUP
Velero
MinIO

------------------------------------------------

SCALING
Metrics Server
HPA
KEDA - optional
```

## Resource-wise, I would target this

For a comfortable **single-node full DevOps lab VM**:

| Resource | Minimum | Recommended |
|---|---:|---:|
| CPU | 8 vCPU | **12–16 vCPU** |
| RAM | 16 GB | **24–32 GB** |
| Disk | 100 GB | **150–200 GB SSD** |
| OS | Ubuntu 24.04 | **Ubuntu 24.04** |

If you only give students something like:

```text
4 CPU
8 GB RAM
40 GB disk
```

then I would reduce it to:

```text
K3s
Jenkins
Argo CD
Trivy
Prometheus
Grafana
Loki
```

and run things such as **SonarQube, Harbor, Vault and MinIO externally/shared**.

The biggest design difference from your **3-node environment** is therefore:

```text
SINGLE NODE                         3 NODE
─────────────────                  ─────────────────

Learn Kubernetes                   Learn Kubernetes + HA

local-path                         Longhorn / distributed storage

Traefik                            Gateway + LoadBalancer options

No node failover                   Node failover

No storage replication            Storage replication

HPA only at pod level              HPA + realistic scheduling

Simple PostgreSQL                  PostgreSQL operator/HA

Basic networking                   Advanced Cilium/eBPF

DevOps learning                    Production platform engineering
```

For your students, I'd actually make the **single-node platform the first stage** and the **3-node cluster the second stage**. That gives you a very natural learning progression:

**Single-node K3s → CI/CD → GitOps → Security → Observability → Stateful apps → Backup → Scaling → then migrate the same application to the 3-node production-style cluster.**