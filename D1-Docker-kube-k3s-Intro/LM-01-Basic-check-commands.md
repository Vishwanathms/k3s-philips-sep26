Yes. For a training session, I would make it **much more compact**—focused on validating the K3s installation rather than teaching every troubleshooting scenario.

# K3s Installation Validation – Lab Manual

**OS:** Ubuntu 24.04
**Duration:** 60–90 minutes
**Prerequisite:** K3s already installed

## Lab Objectives

By the end of this lab, you will verify:

* K3s service
* Kubernetes node
* System pods
* CoreDNS
* Container runtime
* Application deployment
* Service and DNS
* Self-healing
* K3s restart/recovery

---

## Lab 1 – Verify K3s Service

### 1. Check K3s status

```bash
sudo systemctl status k3s
```

Expected:

```text
Active: active (running)
```

### 2. Check K3s version

```bash
k3s --version
```

### 3. Check K3s logs

```bash
sudo journalctl -u k3s -n 30
```

---

## Lab 2 – Verify Kubernetes Cluster

### 1. Check cluster

```bash
kubectl cluster-info
```

### 2. Check node

```bash
kubectl get nodes -o wide
```

Expected:

```text
NAME        STATUS   ROLES
k3s-node    Ready    control-plane,master
```

### 3. Check all system components

```bash
kubectl get pods -A
```

All important pods should normally be in:

```text
Running
```

---

## Lab 3 – Verify CoreDNS

CoreDNS provides DNS resolution inside Kubernetes.

```bash
kubectl get pods -n kube-system | grep coredns
```

Check DNS service:

```bash
kubectl get svc -n kube-system
```

Look for:

```text
kube-dns
```

Check CoreDNS logs:

```bash
kubectl logs -n kube-system deployment/coredns
```

---

## Lab 4 – Verify Container Runtime

K3s uses **containerd**.

Check running containers:

```bash
sudo k3s crictl ps
```

Check all containers:

```bash
sudo k3s crictl ps -a
```

Check containerd process:

```bash
ps aux | grep containerd
```

