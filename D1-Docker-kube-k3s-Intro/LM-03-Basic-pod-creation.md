
---

# Lab 5 – Deploy a Test Application

Create an NGINX deployment:

```bash
kubectl create deployment nginx --image=nginx
```

Check:

```bash
kubectl get deployment
```

```bash
kubectl get pods -o wide
```

Expected:

```text
nginx-xxxxx   1/1   Running
```

---

# Lab 6 – Create a Service

Expose NGINX internally:

```bash
kubectl expose deployment nginx \
  --port=80 \
  --target-port=80 \
  --type=ClusterIP
```

Check:

```bash
kubectl get svc
```

Expected:

```text
nginx   ClusterIP   10.43.x.x
```

---

# Lab 7 – Test Service and DNS

Create a temporary test pod:

```bash
kubectl run test \
  --image=curlimages/curl \
  --rm -it \
  --restart=Never \
  -- sh
```

Inside the pod:

```bash
curl http://nginx
```

You should receive the NGINX HTML response.

Test Kubernetes DNS:

```bash
nslookup nginx
```

Exit:

```bash
exit
```

---

# Lab 8 – Test Kubernetes Self-Healing

Check the NGINX pod:

```bash
kubectl get pods
```

Delete it:

```bash
kubectl delete pod -l app=nginx
```

Immediately check:

```bash
kubectl get pods -w
```

Observe that Kubernetes creates a **new NGINX pod automatically**.

### Why?

The Deployment maintains the desired state:

```text
Desired = 1 Pod

Pod deleted
     ↓
Deployment detects difference
     ↓
New Pod created
     ↓
Running
```