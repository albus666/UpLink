#!/bin/bash
set -euo pipefail

sudo cp /opt/uplink/server/uplink.service /etc/systemd/system/uplink.service
sudo systemctl daemon-reload
sudo systemctl enable --now uplink
sleep 2
sudo systemctl --no-pager --full status uplink || true
echo "=== local health ==="
curl -sS --max-time 8 http://127.0.0.1:8787/api/health || true
echo
echo "=== listeners ==="
ss -lntp | grep 8787 || true
