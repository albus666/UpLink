from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any

_SENSITIVE_SHELL = re.compile(
    r"nginx|systemctl|ufw|iptables|firewalld|firewall-cmd|sshd|/etc/nginx|/etc/systemd|"
    r"/etc/ssh|/etc/sudoers|reboot|shutdown|useradd|userdel|passwd|chown\s+root",
    re.I,
)
_SENSITIVE_PATH = re.compile(
    r"(^|/)\.env($|/|\.|_)|/\.ssh/|/etc/nginx|/etc/systemd|/etc/ssh|"
    r"\.pem($|\?)|\.key($|\?)|id_rsa|id_ed25519|credentials|secrets?\.(json|ya?ml|toml)",
    re.I,
)
_SECRET_TOKENS = re.compile(
    r"CURSOR_API_KEY|AWS_SECRET|api[_-]?key|secret[_-]?key|private[_-]?key|access[_-]?key",
    re.I,
)


@dataclass
class ApprovalRequest:
    sensitive: bool
    summary: str
    tool: str
    detail: str

    def to_dict(self) -> dict[str, str]:
        return {
            "summary": self.summary,
            "tool": self.tool,
            "detail": self.detail,
        }


def _tool_args(tool_call: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    mapping = {
        "shellToolCall": "shell",
        "writeToolCall": "write",
        "editToolCall": "edit",
        "applyPatchToolCall": "patch",
        "deleteToolCall": "delete",
        "readToolCall": "read",
    }
    for key, name in mapping.items():
        if key in tool_call:
            return name, (tool_call[key] or {}).get("args") or {}
    func = tool_call.get("function") or {}
    if func:
        return str(func.get("name") or "tool"), func.get("arguments") or {}
    return "tool", {}


def check_tool_call(tool_call: dict[str, Any]) -> ApprovalRequest:
    tool, args = _tool_args(tool_call)
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except json.JSONDecodeError:
            args = {"raw": args}

    command = str(args.get("command") or args.get("cmd") or "").strip()
    path = str(args.get("path") or args.get("file") or args.get("target") or "").strip()
    patch = str(args.get("patch") or args.get("content") or "").strip()
    blob = " ".join(part for part in [command, path, patch] if part)

    sensitive = False
    if tool == "shell" and _SENSITIVE_SHELL.search(command):
        sensitive = True
    if path and _SENSITIVE_PATH.search(path):
        sensitive = True
    if blob and _SECRET_TOKENS.search(blob):
        sensitive = True
    if tool in {"write", "edit", "patch", "delete"} and path and (
        path.startswith("/etc/") or _SENSITIVE_PATH.search(path)
    ):
        sensitive = True

    if tool == "shell" and command:
        summary = command
    elif path:
        summary = f"{tool} {path}"
    else:
        summary = tool

    detail = summary
    if patch and len(patch) < 240:
        detail = f"{summary}\n{patch}"
    elif patch:
        detail = f"{summary}\n{patch[:240]}…"

    return ApprovalRequest(
        sensitive=sensitive,
        summary=summary[:500],
        tool=tool,
        detail=detail[:800],
    )
