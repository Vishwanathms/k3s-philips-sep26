#!/usr/bin/env bash
# Stage12 G1: create the bare git repo that stands in for "the student's
# GitLab repo" (GitLab itself is a separate VM, not yet provisioned - see
# CAPSTONE/README.md and task.md Phase 16). Durable and served by a
# systemd-managed git-daemon, unlike Day14 ex02's /tmp bare repo which did
# not survive a reboot.
#
# Idempotent: safe to re-run.
set -euo pipefail

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_DIR=/srv/git/capstone-gitops.git
CLONE_DIR="$HOME/capstone-gitops-clone"

if [ ! -d "$REMOTE_DIR" ]; then
  sudo mkdir -p /srv/git
  sudo chown "$(id -un)":"$(id -gn)" /srv/git
  git init --bare --initial-branch=main "$REMOTE_DIR"
fi
touch "$REMOTE_DIR/git-daemon-export-ok"

if ! systemctl is-active --quiet git-daemon.service; then
  echo "git-daemon.service is not active - installing/starting it" >&2
  sudo tee /etc/systemd/system/git-daemon.service > /dev/null <<'UNIT'
[Unit]
Description=git daemon (read-only, for classroom GitOps labs - Argo CD source)
After=network.target

[Service]
User=labuser
Group=labuser
ExecStart=/usr/bin/git daemon --reuseaddr --base-path=/srv/git --export-all --listen=0.0.0.0 --port=9418 /srv/git
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
  sudo systemctl daemon-reload
  sudo systemctl enable --now git-daemon.service
fi

if [ ! -d "$CLONE_DIR/.git" ]; then
  git clone "$REMOTE_DIR" "$CLONE_DIR"
fi

rsync -a --delete --exclude .git "$STAGE_DIR/gitops/" "$CLONE_DIR/"

cd "$CLONE_DIR"
git add -A
if ! git diff --cached --quiet; then
  git -c user.email=labuser@lab-g2-vm2 -c user.name=labuser commit -m "capstone gitops: sync from CAPSTONE/Stage12-ArgoCD/gitops"
else
  echo "clone already matches Stage12-ArgoCD/gitops - nothing to commit" >&2
fi
git push origin main

echo "Remote:  git://$(hostname -I | awk '{print $1}')/capstone-gitops.git"
echo "Clone:   $CLONE_DIR"
