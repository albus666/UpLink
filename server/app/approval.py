from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any

# 密钥 / 凭据文件：读或写都要确认。
_SECRET_PATH = re.compile(
    r"(^|/)\.env($|/|\.|_)|/\.ssh/[\w.-]+|(^|/)\S+\.pem($|\?|\s)|(^|/|\\)\S+\.key($|\?|\s)|"
    r"id_rsa|id_ed25519|credentials|secrets?\.(json|ya?ml|toml)|/etc/shadow|/etc/gshadow",
    re.I,
)
# 系统路径：只有写入、删除、改权限才要确认。
_PROTECTED_PATH = re.compile(
    r"/etc/nginx|/etc/systemd|/etc/ssh|/etc/sudoers|"
    r"(^|/)\.env($|/|\.|_)|/\.ssh/|\.pem($|\?)|\.key($|\?)|"
    r"id_rsa|id_ed25519|credentials|secrets?\.(json|ya?ml|toml)",
    re.I,
)
_SECRET_TOKENS = re.compile(
    r"CURSOR_API_KEY|AWS_SECRET|api[_-]?key|secret[_-]?key|private[_-]?key|access[_-]?key",
    re.I,
)

_MUTATING_SYSTEMCTL = re.compile(
    r"\bsystemctl\s+(?:start|stop|restart|reload|try-reload-or-restart|enable|disable|"
    r"mask|unmask|isolate|kill|edit|set-default|daemon-reload|reset-failed|"
    r"add-wants|set-property|reboot|poweroff)\b",
    re.I,
)
_MUTATING_SERVICE = re.compile(r"\bservice\s+\S+\s+(?:start|stop|restart|reload)\b", re.I)
_MUTATING_NGINX = re.compile(r"\bnginx\s+(?:-\s*)?(?:-s\s+)?(?:reload|stop|quit)\b", re.I)
_MUTATING_UFW = re.compile(r"\bufw\s+(?!status\b|show\b|version\b|app\s+list\b|--help\b)", re.I)
_MUTATING_IPTABLES = re.compile(
    r"\b(?:ip6tables|iptables)\b[^\n]*"
    r"(?:\s-[ADIRFPXE](?:\s|$)|"
    r"\s-N\s+\S|"
    r"\s--(?:append|delete|insert|replace|flush|policy|new-chain|delete-chain|rename-chain)\b)",
    re.I,
)
_MUTATING_FIREWALL = re.compile(
    r"\bfirewall-cmd\b(?!.*--(?:list[\w-]*|state|query[\w-]*|get[\w-]*|help|info|version)\b)",
    re.I,
)
_POWER = re.compile(r"\b(?:reboot|shutdown|halt|poweroff|init\s+[06])\b", re.I)
_USERS = re.compile(r"\b(?:useradd|userdel|usermod|passwd|visudo|chage)\b", re.I)
_CHOWN_ROOT = re.compile(r"\bchown\s+(?:-[^\s]+\s+)*root\b", re.I)
_PROTECTED_WRITE = re.compile(
    r"(?:>>?|tee(?:\s+-a)?)\s*['\"]?(?:/etc/|\S*\.env(?:$|\.|\s)|\S*\.pem(?:$|\s)|\S*/\.ssh/)",
    re.I,
)
_PROTECTED_FILE_OP = re.compile(
    r"\b(?:rm|mv|cp|install|chmod|chown|mkdir|touch|truncate|tee|unlink)\b"
    r".*(?:/etc/|/etc/nginx|/etc/systemd|/etc/ssh|\.ssh/|\.env(?:$|\.|\s)|\.pem(?:$|\s))",
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


def _shell_needs_approval(command: str) -> bool:
    text = command.strip()
    if not text:
        return False
    if _SECRET_PATH.search(text) or _SECRET_TOKENS.search(text):
        return True
    if _MUTATING_SYSTEMCTL.search(text):
        return True
    if _MUTATING_SERVICE.search(text):
        return True
    if _MUTATING_NGINX.search(text):
        return True
    if _MUTATING_UFW.search(text):
        return True
    if _MUTATING_IPTABLES.search(text):
        return True
    if _MUTATING_FIREWALL.search(text):
        return True
    if _POWER.search(text):
        return True
    if _USERS.search(text):
        return True
    if _CHOWN_ROOT.search(text):
        return True
    if _PROTECTED_WRITE.search(text) or _PROTECTED_FILE_OP.search(text):
        return True
    return False


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
    if tool == "shell" and command and _shell_needs_approval(command):
        sensitive = True
    if tool == "read" and path and _SECRET_PATH.search(path):
        sensitive = True
    if tool in {"write", "edit", "patch", "delete"} and path and (
        path.startswith("/etc/") or _PROTECTED_PATH.search(path)
    ):
        sensitive = True
    if blob and _SECRET_TOKENS.search(blob):
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
