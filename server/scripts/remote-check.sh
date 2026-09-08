#!/bin/bash
set +e
echo "=== .env keys ==="
grep -E '^[A-Z_]+=' /opt/uplink/server/.env | cut -d= -f1
echo "=== parsed settings ==="
/usr/bin/python3 - <<'PY'
from pathlib import Path
text = Path("/opt/uplink/server/.env").read_text()
vals = {}
for line in text.splitlines():
    if not line.strip() or line.strip().startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    vals[k.strip()] = v.strip()
print("APP_TOKEN_LEN", len(vals.get("APP_TOKEN", "")))
print("WORKSPACE", vals.get("WORKSPACE"))
print("AGENT_BIN", vals.get("AGENT_BIN"))
print("HOST", vals.get("HOST"))
print("PORT", vals.get("PORT"))
key = vals.get("CURSOR_API_KEY", "")
print("CURSOR_API_KEY_PREFIX", key[:4] if key else "EMPTY")
print("CURSOR_API_KEY_LEN", len(key))
print("AGENT_BIN_EXISTS", Path(vals.get("AGENT_BIN", "")).exists())
print("WORKSPACE_EXISTS", Path(vals.get("WORKSPACE", ".")).exists())
PY
echo "=== venv ==="
/opt/uplink/server/.venv/bin/python -c "import fastapi,uvicorn,pydantic_settings; print('ok', fastapi.__version__)"
echo "=== agent ==="
export PATH="$HOME/.local/bin:$PATH"
agent --version || true
agent status || true
echo "=== port ==="
ss -lntp | grep 8787 || echo "not listening"
echo "=== unit ==="
cat /opt/uplink/server/uplink.service
ls -l /etc/systemd/system/uplink.service 2>/dev/null || echo "unit not installed"
systemctl is-enabled uplink 2>/dev/null || true
systemctl is-active uplink 2>/dev/null || true
