
---

# Lab 9 – Restart K3s

Restart the K3s service:

```bash
sudo systemctl restart k3s
```

Check:

```bash
sudo systemctl status k3s
```

Then:

```bash
kubectl get nodes
```

```bash
kubectl get pods -A
```

Verify that the node returns to:

```text
Ready
```

and workloads return to:

```text
Running
```

---

# Lab 10 – Final Health Check

Run these commands:

```bash
sudo systemctl is-active k3s
```

```bash
kubectl get nodes
```

```bash
kubectl get pods -A
```

```bash
kubectl get svc -A
```

```bash
sudo k3s crictl ps
```
