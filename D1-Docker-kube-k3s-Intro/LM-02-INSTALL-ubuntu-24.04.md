# Installing K3s on Ubuntu 24.04 LTS

Step-by-step for a **single-node** cluster (control plane + workloads on one
machine), with notes for adding agents and HA. See [PREREQUISITES.md](PREREQUISITES.md)
for the full requirements list.

Tested target: Ubuntu 24.04.4 LTS (Noble), x86_64, cgroup v2.

---

## 0. Conventions

- Run everything as a user with `sudo`. Commands that must be root are shown with `sudo`.
- `<SERVER_IP>` = the node's LAN IP (here: check with `ip -4 addr show ens192`).
- K3s version is pinned for reproducibility — pick a current stable from
  https://github.com/k3s-io/k3s/releases and set it below.

```bash
export K3S_VERSION="v1.31.5+k3s1"   # <-- set to a current stable release
```

---

## 1. Prepare the OS

### 1.1 Update and install helpers

```bash
sudo apt-get update
sudo apt-get install -y curl apt-transport-https ca-certificates
```

### 1.2 Disable swap

Kubernetes expects swap off.

```bash
sudo swapoff -a
sudo sed -i.bak -E '/\sswap\s/ s/^/#/' /etc/fstab
# Ubuntu 24.04 cloud/desktop images use a swapfile unit or /swap.img:
sudo systemctl mask swap.target 2>/dev/null || true
free -h   # confirm Swap total = 0
```

> If `/swap.img` is listed in `/etc/fstab`, the `sed` above comments it out.
> Reboot later to confirm it stays off.

### 1.3 Kernel modules and sysctls

```bash
cat <<'EOF' | sudo tee /etc/modules-load.d/k3s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<'EOF' | sudo tee /etc/sysctl.d/99-k3s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

### 1.4 Time sync

```bash
timedatectl   # "System clock synchronized: yes", "NTP service: active"
# if not:
sudo apt-get install -y systemd-timesyncd && sudo timedatectl set-ntp true
```

### 1.5 Firewall

Ubuntu ships **ufw**. For a single-node lab the simplest path is to leave ufw
disabled (default on Server/Desktop). If ufw is enabled, open the K3s ports:

```bash
sudo ufw status    # if "inactive", nothing to do

# only if active:
sudo ufw allow 6443/tcp        comment 'k3s API'
sudo ufw allow from 10.42.0.0/16   comment 'k3s pods'
sudo ufw allow from 10.43.0.0/16   comment 'k3s services'
# multi-node also needs:
sudo ufw allow 10250/tcp       comment 'kubelet'
sudo ufw allow 8472/udp        comment 'flannel vxlan'
sudo ufw reload
```

### 1.6 Check CIDR overlap

K3s uses `10.42.0.0/16` (pods) and `10.43.0.0/16` (services) by default.
Confirm nothing on the host already uses those ranges:

```bash
ip -o -f inet addr show | awk '{print $2, $4}'
```

Docker's default `172.17.0.0/16` / `172.18.0.0/16` do **not** clash — fine to
leave Docker installed.

---

## 2. Install K3s (server)

### 2.1 Run the installer

```bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  sh -s - server \
    --write-kubeconfig-mode 0644 \
    --node-name "$(hostnamectl --static)" \
    --tls-san "$(hostname -I | awk '{print $1}')"
```

What this does:
- installs `/usr/local/bin/k3s` (+ `kubectl`, `crictl`, `ctr` symlinks)
- creates and starts the `k3s.service` systemd unit
- brings up containerd (bundled, at `/run/k3s/containerd/containerd.sock`),
  Flannel CNI, CoreDNS, Traefik ingress, ServiceLB, local-path storage,
  metrics-server
- writes kubeconfig to `/etc/rancher/k3s/k3s.yaml`

`--write-kubeconfig-mode 0644` lets non-root users read the kubeconfig.
`--tls-san` adds the node IP to the API cert so remote `kubectl` works.

### 2.2 Wait for readiness

```bash
sudo systemctl status k3s --no-pager
sudo k3s kubectl get nodes -w      # Ctrl-C when STATUS = Ready
```

---

## 3. Configure kubectl

### 3.1 On the node

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
export KUBECONFIG=~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc

kubectl get nodes
kubectl get pods -A
```

> A system `kubectl` (e.g. `/usr/local/bin/kubectl`) works fine against K3s.
> The K3s-bundled one is `k3s kubectl`.

### 3.2 From a remote workstation

```bash
scp user@<SERVER_IP>:/etc/rancher/k3s/k3s.yaml ./k3s-config
sed -i "s/127.0.0.1/<SERVER_IP>/" ./k3s-config
KUBECONFIG=./k3s-config kubectl get nodes
```

---

## 4. Smoke test

```bash
kubectl create deployment web --image=nginx --replicas=2
kubectl expose deployment web --port=80 --type=NodePort
kubectl rollout status deployment/web
NODEPORT=$(kubectl get svc web -o jsonpath='{.spec.ports[0].nodePort}')
curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://<SERVER_IP>:${NODEPORT}"   # -> HTTP 200

kubectl delete deployment web && kubectl delete svc web
```

> **Why NodePort, not LoadBalancer, here:** Traefik's ServiceLB already binds
> host ports 80/443. A second `type=LoadBalancer` service on port 80 stays
> `EXTERNAL-IP <pending>` with its `svclb-*` pod `Pending` ("didn't have free
> ports") — expected on a single node. Route real HTTP through the Traefik
> Ingress instead, or give the service a different port.

Storage test:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: test-pvc }
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources: { requests: { storage: 100Mi } }
EOF
kubectl get pvc test-pvc      # Bound once a pod consumes it
kubectl delete pvc test-pvc
```

---

## 5. Add worker (agent) nodes — optional

On the **server**:

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

On each **agent** (Ubuntu 24.04, same OS prep as §1):

```bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  K3S_URL="https://<SERVER_IP>:6443" \
  K3S_TOKEN="<node-token>" \
  sh -s - agent --node-name "$(hostnamectl --static)"
```

Back on the server: `kubectl get nodes` should list the agent.

---

## 6. HA control plane — optional

First server:

```bash
curl -sfL https://get.k3s.io | sh -s - server --cluster-init \
  --tls-san <LB_IP_OR_DNS>
```

Additional servers (odd total — 3 or 5):

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --server https://<FIRST_SERVER_IP>:6443 \
  --token <node-token> \
  --tls-san <LB_IP_OR_DNS>
```

Put an L4 load balancer (or DNS round-robin) on port 6443 in front of the
servers and point agents / kubeconfig at it.

---

## 7. Common customizations

Put flags in `/etc/rancher/k3s/config.yaml` instead of the install command so
they survive upgrades:

```yaml
# /etc/rancher/k3s/config.yaml
write-kubeconfig-mode: "0644"
tls-san:
  - "192.168.230.103"
disable:
  - traefik          # if you want to install your own ingress
# cluster-cidr: "10.42.0.0/16"
# service-cidr: "10.43.0.0/16"
```

Apply with `sudo systemctl restart k3s`.

---

## 8. Upgrade / uninstall

```bash
# upgrade: re-run the installer with a newer INSTALL_K3S_VERSION, then:
sudo systemctl restart k3s

# uninstall server:
sudo /usr/local/bin/k3s-uninstall.sh
# uninstall agent:
sudo /usr/local/bin/k3s-agent-uninstall.sh
```

---

## 9. Troubleshooting

| Symptom | Check |
|---------|-------|
| Node stuck `NotReady` | `sudo journalctl -u k3s -f`; CNI pod logs |
| `kubectl` connection refused | `sudo systemctl status k3s`; is 6443 listening? `ss -tlnp \| grep 6443` |
| Pods can't resolve DNS | `kubectl -n kube-system get pods -l k8s-app=kube-dns`; check `br_netfilter` + sysctls (§1.3) |
| Image pull fails | outbound 443 to `docker.io` / `registry.k8s.io`; or configure `/etc/rancher/k3s/registries.yaml` |
| LoadBalancer svc `<pending>` | ServiceLB needs a free host port; check `kubectl -n kube-system get pods -l app=svclb-*` |
| Swap re-enabled after reboot | re-check `/etc/fstab` and any `swap.img` systemd unit |

Logs: `sudo journalctl -u k3s -f` (server) or `-u k3s-agent -f` (agent).
