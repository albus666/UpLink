#!/bin/bash
set -euo pipefail
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/known_hosts"
ssh-keyscan -t ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
cd /opt/uplink
git remote set-url origin git@github.com:albus666/UpLink.git
ssh -T -o IdentitiesOnly=yes -i "$HOME/.ssh/uplink_github" git@github.com || true
git fetch origin
git checkout -- .
git pull --ff-only origin master
git log -1 --oneline
sudo cp /opt/uplink/server/uplink.service /etc/systemd/system/uplink.service
sudo systemctl daemon-reload
sudo systemctl enable uplink
sudo systemctl restart uplink
sleep 2
systemctl is-enabled uplink
systemctl is-active uplink
curl -sS --max-time 8 http://127.0.0.1:8787/api/health
echo
