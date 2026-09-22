# ex01 — simple nginx

A `Deployment` (2 nginx replicas) fronted by a `NodePort` `Service`.

> ✅ **Verified on the live cluster — captured output in [OUTPUT.md](OUTPUT.md).**

## Apply

```bash
kubectl apply -f nginx.yaml
kubectl rollout status deployment/nginx
kubectl get pods -l app=nginx -o wide
```

## Test

```bash
# discover the assigned NodePort and the node's IP
NP=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
HOST=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "http://$HOST:$NP"

curl -s -o /dev/null -w "HTTP %{http_code}\n" --retry 5 --retry-connrefused "http://$HOST:$NP"
# -> HTTP 200   (NodePort iptables rules can lag a second or two after rollout)

# or without a NodePort, via port-forward:
kubectl port-forward svc/nginx 8080:80 &
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8080
kill %1
```

## Inspect

```bash
kubectl describe deployment nginx
kubectl get endpoints nginx        # the 2 pod IPs behind the Service
kubectl logs -l app=nginx --tail=5
```

## Clean up

```bash
kubectl delete -f nginx.yaml
```

## Key ideas

| Object | Role |
|--------|------|
| Deployment | declares desired state (image, replica count); recreates pods that die |
| ReplicaSet | created by the Deployment; the thing actually keeping N pods running |
| Service | stable virtual IP + DNS name (`nginx.default.svc.cluster.local`) load-balancing to the pods matched by `selector` |
| NodePort | opens the same port on every node so traffic from outside the cluster can reach the Service |
