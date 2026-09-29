Below is a **clean lab manual for a single-node K3s cluster**, specifically demonstrating recovery when a **major/minor K3s upgrade fails**.

> **Important:** Kubernetes/K3s terminology usually calls `v1.35 → v1.36` a **minor-version upgrade**, not a major-version upgrade. This lab uses that scenario because K3s's documented rollback procedure applies to previous Kubernetes minor versions. A rollback requires a datastore snapshot from the old version. ([K3s Documentation][1])

# Lab: Roll Back a Failed K3s Version Upgrade

## 1. Lab Objective

In this lab you will:

1. Create a single-node K3s cluster.
2. Deploy a sample application.
3. Record the current K3s version.
4. Create a pre-upgrade datastore snapshot.
5. Upgrade K3s.
6. Simulate/demonstrate an unsuccessful upgrade.
7. Stop K3s.
8. Restore the previous K3s version.
9. Restore the pre-upgrade datastore.
10. Verify that the cluster and application are working again.

### Architecture

```text
                Single Ubuntu VM
              ┌──────────────────────┐
              │                      │
              │      K3s Server      │
              │                      │
              │  Kubernetes API      │
              │  Scheduler           │
              │  Controller Manager  │
              │  Embedded etcd       │
              │  Containerd          │
              │                      │
              └──────────────────────┘
                         │
                         ▼
                  Sample Application
```

---

# 2. Prerequisites

Ubuntu VM with:

```text
CPU       : 2+
RAM       : 4 GB+
Disk      : 30 GB+
OS        : Ubuntu 22.04/24.04
```

Check:

```bash
cat /etc/os-release
```

Check K3s:

```bash
k3s --version
```

Check cluster:

```bash
sudo kubectl get nodes
```

Expected:

```text
NAME        STATUS   ROLES
k3s-server  Ready    control-plane,master
```

---

# 3. Create a Test Application

Create a namespace:

```bash
sudo kubectl create namespace upgrade-lab
```

Deploy nginx:

```bash
sudo kubectl create deployment nginx \
  --image=nginx:1.27 \
  -n upgrade-lab
```

Check:

```bash
sudo kubectl get pods -n upgrade-lab
```

Expected:

```text
NAME                     READY   STATUS
nginx-xxxxxxxxxx-xxxxx   1/1     Running
```

Create a service:

```bash
sudo kubectl expose deployment nginx \
  --port=80 \
  --type=ClusterIP \
  -n upgrade-lab
```

Verify:

```bash
sudo kubectl get all -n upgrade-lab
```

---

# 4. Record the Current K3s Version

Run:

```bash
k3s --version
```

Example:

```text
k3s version v1.35.5+k3s1
```

Also:

```bash
sudo kubectl get nodes -o wide
```

Save this information.

For this lab, we'll call the old version:

```text
OLD_VERSION=v1.35.5+k3s1
```

> Replace this with the **actual version installed on your machine**.

---

# 5. Check the Datastore

Run:

```bash
sudo ls -l /var/lib/rancher/k3s/server/db/
```

For this rollback lab we want **embedded etcd**.

Check:

```bash
sudo ls -ld /var/lib/rancher/k3s/server/db/etcd
```

If that directory exists, you are using embedded etcd.

If you are using SQLite instead, the backup/restore procedure is different. K3s documents SQLite rollback separately. ([K3s Documentation][1])

---

# 6. Backup the K3s Server Token

This is **critical**.

Run:

```bash
sudo cp \
/var/lib/rancher/k3s/server/token \
/root/k3s-server-token-pre-upgrade
```

Verify:

```bash
sudo ls -l /root/k3s-server-token-pre-upgrade
```

K3s requires the original server token when restoring a datastore because the token is used to encrypt confidential data stored in the datastore. ([K3s Documentation][2])

---

# 7. Backup K3s Configuration

Create a backup:

```bash
sudo cp -a \
/etc/rancher/k3s \
/root/k3s-config-pre-upgrade
```

Verify:

```bash
sudo ls -la /root/k3s-config-pre-upgrade
```

This is particularly important if you have custom settings such as:

```text
flannel-backend
disable
tls-san
node-ip
advertise-address
secrets-encryption
datastore configuration
```

---

# 8. Create the Pre-Upgrade etcd Snapshot

This is the **most important step**.

Run:

```bash
sudo k3s etcd-snapshot save \
  --name pre-upgrade
```

Check the snapshot:

```bash
sudo k3s etcd-snapshot ls
```

You should see something similar to:

```text
pre-upgrade-xxxxx
```

K3s supports on-demand snapshots with `k3s etcd-snapshot save`; snapshots are stored on the node filesystem unless you configure S3-compatible storage. ([K3s Documentation][3])

---

# 9. Locate the Snapshot

Run:

```bash
sudo find /var/lib/rancher/k3s/server/db \
  -name '*pre-upgrade*' -type f
```

You should get something similar to:

```text
/var/lib/rancher/k3s/server/db/snapshots/pre-upgrade-xxxxx
```

Record the **exact path**.

For example:

```bash
SNAPSHOT=/var/lib/rancher/k3s/server/db/snapshots/pre-upgrade-xxxxx
```

---

# 10. Verify the Cluster Before Upgrade

Run:

```bash
sudo kubectl get nodes
```

Then:

```bash
sudo kubectl get pods -A
```

And:

```bash
sudo kubectl get pods -n upgrade-lab
```

Make sure your nginx Pod is:

```text
Running
```

Also check:

```bash
sudo systemctl status k3s
```

Everything should be healthy before proceeding.

---

# 11. Upgrade K3s

**Do not blindly use the latest version in a production lab.**

For this exercise, select a specific target version compatible with your starting version.

Example:

```bash
NEW_VERSION=v1.36.x+k3s1
```

Then:

```bash
curl -sfL https://get.k3s.io | \
INSTALL_K3S_VERSION="$NEW_VERSION" sh -
```

K3s's upgrade documentation recommends upgrading through supported Kubernetes minor versions rather than skipping intermediate minor versions. ([K3s Documentation][4])

---

# 12. Verify the Upgrade

Check:

```bash
k3s --version
```

Then:

```bash
sudo kubectl get nodes
```

And:

```bash
sudo kubectl get pods -A
```

Check the service:

```bash
sudo systemctl status k3s
```

Check logs:

```bash
sudo journalctl -u k3s -n 100 --no-pager
```

---

# 13. Identify an Upgrade Failure

For the lab, assume the upgrade has failed.

For example:

```text
K3s service
     ↓
FAILED
```

or:

```text
Kubernetes API
     ↓
Unavailable
```

or:

```text
Application
     ↓
Not functioning
```

Check:

```bash
sudo systemctl status k3s
```

and:

```bash
sudo journalctl -u k3s -n 200 --no-pager
```

At this point:

> **Do not continue troubleshooting by modifying the datastore.**

Your objective is now to perform a controlled rollback.

---

# 14. Record the Failure

In a real production incident, record:

```text
Old K3s version:
New K3s version:

Upgrade time:

Failure symptom:

K3s status:

API status:

Application status:
```

For example:

```text
Old version : v1.35.5+k3s1
New version : v1.36.4+k3s1

Failure:
K3s API server unavailable

Snapshot:
pre-upgrade-xxxxx
```

---

# 15. Stop K3s

Stop the service:

```bash
sudo systemctl stop k3s
```

Verify:

```bash
sudo systemctl status k3s
```

For a rollback, K3s documentation uses `k3s-killall.sh` to stop K3s and running Pod processes where appropriate. Be aware that forcefully terminating processes can cause application-level data loss if applications have not been shut down cleanly. ([K3s Documentation][1])

For this single-node lab, you can use:

```bash
sudo /usr/local/bin/k3s-killall.sh
```

if necessary.

---

# 16. Install the Previous K3s Version

Now reinstall the **exact version that was running before the upgrade**.

Example:

```bash
OLD_VERSION=v1.35.5+k3s1
```

Run:

```bash
curl -sfL https://get.k3s.io | \
INSTALL_K3S_VERSION="$OLD_VERSION" \
INSTALL_K3S_SKIP_START=true \
sh -
```

The `INSTALL_K3S_SKIP_START=true` option is important because we don't want the old K3s binary to start against the upgraded datastore before restoration. K3s documents this approach for rollback. ([K3s Documentation][1])

Verify:

```bash
k3s --version
```

Expected:

```text
k3s version v1.35.5+k3s1
```

---

# 17. Verify the Snapshot Path

Run:

```bash
sudo k3s etcd-snapshot ls
```

If necessary:

```bash
sudo find /var/lib/rancher/k3s/server/db \
  -name '*pre-upgrade*' -type f
```

Set the path:

```bash
SNAPSHOT=/var/lib/rancher/k3s/server/db/snapshots/pre-upgrade-xxxxx
```

---

# 18. Restore the etcd Snapshot

This is the critical rollback operation.

Run:

```bash
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path="$SNAPSHOT"
```

You should see a message similar to:

```text
Managed etcd cluster membership has been reset,
restart without --cluster-reset flag now.
```

K3s's documented single-server restore process uses `--cluster-reset` together with `--cluster-reset-restore-path`. ([K3s Documentation][3])

### Important

**Do not run this command twice.**

K3s creates a reset flag specifically to prevent accidental repeated cluster resets. ([K3s Documentation][3])

---

# 19. Start K3s Normally

Now start K3s:

```bash
sudo systemctl start k3s
```

Check:

```bash
sudo systemctl status k3s
```

---

# 20. Verify the K3s Version

Run:

```bash
k3s --version
```

Expected:

```text
v1.35.5+k3s1
```

You have now rolled back the K3s binary.

---

# 21. Verify the Kubernetes Cluster

Run:

```bash
sudo kubectl get nodes
```

Expected:

```text
NAME        STATUS   ROLES
k3s-server  Ready    control-plane,master
```

Then:

```bash
sudo kubectl get pods -A
```

---

# 22. Verify Your Application

Check:

```bash
sudo kubectl get pods -n upgrade-lab
```

Expected:

```text
nginx-xxxxxxxxxx-xxxxx   1/1   Running
```

Check the deployment:

```bash
sudo kubectl get deployment -n upgrade-lab
```

Check the service:

```bash
sudo kubectl get svc -n upgrade-lab
```

---

# 23. Verify Kubernetes Objects

This is an important part of the lab.

Run:

```bash
sudo kubectl get namespace upgrade-lab
```

Then:

```bash
sudo kubectl get deployment nginx \
  -n upgrade-lab
```

Then:

```bash
sudo kubectl get pods \
  -n upgrade-lab
```

You are verifying that the Kubernetes objects that existed **before the failed upgrade** are back.

---

# 24. Final Health Check

Run:

```bash
sudo systemctl status k3s
```

```bash
sudo kubectl get nodes
```

```bash
sudo kubectl get pods -A
```

```bash
sudo kubectl get --raw='/readyz?verbose'
```

Finally:

```bash
sudo journalctl -u k3s \
  --since "10 minutes ago" \
  --no-pager
```

Look for errors.

---

# 25. Rollback Flow

Your complete lab flow is:

```text
                 SINGLE NODE K3S
                       │
                       ▼
              Record old version
                       │
                       ▼
              Backup K3s config
                       │
                       ▼
               Backup token
                       │
                       ▼
             Create etcd snapshot
                       │
                       ▼
                 Upgrade K3s
                       │
                       ▼
                 Test cluster
                       │
                ┌──────┴──────┐
                │             │
              PASS           FAIL
                │             │
                ▼             ▼
             Continue      STOP K3s
                              │
                              ▼
                     Install OLD binary
                              │
                              ▼
                       Restore snapshot
                              │
                              ▼
                       Start K3s
                              │
                              ▼
                     Verify cluster
                              │
                              ▼
                     Verify application
```

---

# 26. Recovery Checklist

| Step                 | Command                  | Required     |
| -------------------- | ------------------------ | ------------ |
| Record version       | `k3s --version`          | ✅            |
| Check nodes          | `kubectl get nodes`      | ✅            |
| Backup config        | `/etc/rancher/k3s`       | ✅            |
| Backup token         | `server/token`           | **Critical** |
| Create etcd snapshot | `k3s etcd-snapshot save` | **Critical** |
| Upgrade              | K3s installer            |              |
| Detect failure       | `systemctl/journalctl`   |              |
| Stop K3s             | `systemctl stop k3s`     |              |
| Install old binary   | `INSTALL_K3S_VERSION`    |              |
| Restore datastore    | `--cluster-reset`        | **Critical** |
| Start K3s            | `systemctl start k3s`    |              |
| Verify               | `kubectl get nodes/pods` | **Critical** |

---

## 27. What You Must Have Before Starting

For a **single-node K3s rollback**, the three most important items are:

```text
┌──────────────────────────────────────────┐
│          PRE-UPGRADE BACKUP              │
├──────────────────────────────────────────┤
│                                          │
│  1. OLD K3s VERSION                     │
│     v1.35.x+k3s1                        │
│                                          │
│  2. ETCD SNAPSHOT                        │
│     pre-upgrade-xxxxx                    │
│                                          │
│  3. SERVER TOKEN                         │
│     /var/lib/rancher/k3s/server/token   │
│                                          │
└──────────────────────────────────────────┘
```

**Without a datastore snapshot from the old minor version, K3s does not support rolling back to that previous minor version.** ([K3s Documentation][1])

Also, don't rely on the snapshot alone: K3s explicitly requires preserving the server token for datastore restoration. ([K3s Documentation][2])

### Optional enhancement for your VMware lab

Because your K3s environment is running in a VM, I would make the lab even safer:

```text
             BEFORE UPGRADE
                   │
          ┌────────┴─────────┐
          │                  │
    VMware Snapshot      K3s Backup
          │                  │
          │             ┌────┴─────┐
          │             │          │
          │          etcd       token
          │
          └──────────┬─────────────┘
                     │
                  UPGRADE
                     │
                 FAILURE
                     │
              ┌──────┴──────┐
              │             │
          K3s Restore   VM Snapshot
```

That gives you a **Kubernetes-aware rollback path** plus a **full VM recovery path**. For training labs, this is particularly useful because you can demonstrate both recovery methods without risking the original environment.

[1]: https://docs.k3s.io/upgrades/roll-back?utm_source=chatgpt.com "Rolling Back K3s | K3s"
[2]: https://docs.k3s.io/datastore/backup-restore?utm_source=chatgpt.com "Backup and Restore | K3s"
[3]: https://docs.k3s.io/cli/etcd-snapshot?utm_source=chatgpt.com "etcd-snapshot | K3s"
[4]: https://docs.k3s.io/upgrades/manual?utm_source=chatgpt.com "Manual Upgrades | K3s"
