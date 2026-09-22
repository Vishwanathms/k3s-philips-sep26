# Lab 01 — Deploy and Expose Nginx on k3s

## Objective

By the end of this lab, you will be able to:

- Write a Kubernetes manifest containing a `Deployment` and a `Service`.
- Apply the manifest to a k3s cluster and verify the rollout.
- Understand how a `Deployment` manages `ReplicaSet`s and `Pod`s.
- Reach an application running inside the cluster from outside it, using a `NodePort` Service.
- Inspect and clean up the resources you created.

## Prerequisites

- Access to a running k3s cluster (single node or multi-node).
- `kubectl` configured to talk to the cluster (on the k3s node itself, or via a copied `kubeconfig`).
- Basic familiarity with YAML and the terminal.

Verify your cluster access before starting:

```bash
kubectl get nodes
```

You should see at least one node in `Ready` state.

## Background

| Concept | What it means here |
|---|---|
| **Deployment** | A controller object that declares the desired state of your app: which image to run, how many replicas, resource limits. It creates and manages a `ReplicaSet`. |
| **ReplicaSet** | Created automatically by the Deployment. Its only job is to keep the requested number of Pods running — if one dies, it creates a replacement. |
| **Pod** | The smallest deployable unit — one or more containers sharing network/storage. Here, one `nginx` container per Pod. |
| **Service** | A stable virtual IP and DNS name that load-balances traffic across all Pods matching its `selector`, even as Pods are replaced and their IPs change. |
| **NodePort** | A Service type that opens the same port (30000-32767) on *every* node in the cluster, so traffic from outside the cluster can reach the Service without an Ingress controller. |

> Why NodePort here and not Ingress? k3s ships with Traefik as its default Ingress controller, already bound to ports 80/443 on the node. Using NodePort for this first exercise avoids touching Traefik and lets you reach the app directly.

## Step 1 — Review the manifest

Open [nginx.yaml](nginx.yaml) and read through it before applying anything. Identify:

1. Where the desired replica count is set.
2. Which label connects the Deployment's Pods to the Service's `selector`.
3. Which container port is exposed, and how it maps to the Service's `port` / `targetPort`.

<details>
<summary>Answer key</summary>

1. `spec.replicas: 2` under the Deployment.
2. `app: nginx` — set as a Pod label in the Deployment template, and matched by `spec.selector` in both the Deployment and the Service.
3. `containerPort: 80` on the Pod; the Service listens on `port: 80` and forwards to `targetPort: 80` on the Pod.

</details>

## Step 2 — Apply the manifest

```bash
kubectl apply -f nginx.yaml
kubectl rollout status deployment/nginx
```

`rollout status` blocks until all replicas are up, or times out. Wait for `successfully rolled out` before continuing.

## Step 3 — Confirm the Pods are running

```bash
kubectl get pods -l app=nginx -o wide
```

Expected: 2 pods, `STATUS Running`, `READY 1/1`, each with a distinct pod IP on the `10.42.0.0/16` range (k3s's default pod CIDR).

Also look at the ReplicaSet that the Deployment created for you:

```bash
kubectl get rs -l app=nginx
```

## Step 4 — Reach nginx from outside the cluster

k3s assigned a random port in `30000-32767` to the Service. Discover it and the node's IP, then curl it:

```bash
NP=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
HOST=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "http://$HOST:$NP"

curl -s -o /dev/null -w "HTTP %{http_code}\n" --retry 5 --retry-connrefused "http://$HOST:$NP"
```

Expected output: `HTTP 200`.

> If you get connection refused immediately after apply, wait a second or two — the NodePort iptables rules on each node take a brief moment to program after rollout.

### Alternative: port-forward (no NodePort needed)

```bash
kubectl port-forward svc/nginx 8080:80 &
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8080
kill %1
```

`port-forward` tunnels directly from your machine to the Service, useful when you don't want to expose a NodePort at all.

## Step 5 — Inspect what got created

```bash
kubectl describe deployment nginx
kubectl get endpoints nginx        # one entry per pod backing the Service
kubectl logs -l app=nginx --tail=5
```

`kubectl get endpoints nginx` is the key command to understand *how* a Service finds its Pods: it lists the actual `podIP:port` pairs currently matching the Service's selector. Compare this list to the Pod IPs from Step 3 — they should match.

> Note: `v1 Endpoints` is deprecated from Kubernetes v1.33+ in favor of `discovery.k8s.io/v1 EndpointSlice`. You may see a deprecation warning — it's harmless. Try `kubectl get endpointslices` as the modern equivalent.

## Step 6 — Clean up

```bash
kubectl delete -f nginx.yaml
```

Confirm both the deployment and service are gone:

```bash
kubectl get deploy,svc -l app=nginx
```

Should return `No resources found`.

## Checkpoint questions

1. If you `kubectl delete pod <one-of-the-nginx-pods>` manually, what happens, and why?
2. Why does the Service keep working even though each Pod has a different IP?
3. What would change in the manifest if you wanted the app reachable on the same port from every node without relying on a random high port?

<details>
<summary>Answers</summary>

1. The ReplicaSet notices the actual Pod count (1) no longer matches the desired count (2) and creates a replacement Pod immediately. The Deployment itself doesn't do this directly — the ReplicaSet it owns does.
2. The Service is a stable abstraction: its `selector` continuously matches whichever Pods currently carry the `app: nginx` label, and `kube-proxy` programs the routing rules (iptables/IPVS) to load-balance across their current IPs. Clients only ever talk to the Service's virtual IP/DNS name.
3. Set a fixed `nodePort:` value (within 30000-32767) under the Service's port definition instead of leaving it to be auto-assigned, or switch the Service type to `LoadBalancer`/use an `Ingress` for standard port 80/443 access.

</details>

## Reference: verified run

A full captured run of this exact lab (commands + output) is available in [OUTPUT.md](OUTPUT.md) for comparison against your own results.
