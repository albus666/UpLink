from __future__ import annotations

from pathlib import Path
from typing import Any

from .paths import resolve_inside

TEXT_EXTS = {
    ".txt",
    ".md",
    ".markdown",
    ".py",
    ".pyi",
    ".json",
    ".yaml",
    ".yml",
    ".toml",
    ".ini",
    ".cfg",
    ".conf",
    ".xml",
    ".html",
    ".css",
    ".js",
    ".ts",
    ".dart",
    ".sh",
    ".bash",
    ".zsh",
    ".service",
    ".log",
    ".csv",
    ".svg",
    ".gitignore",
    ".dockerignore",
    ".example",
    ".env.example",
}

BLOCKED_PARTS = {".ssh", ".gnupg", ".aws", ".docker"}
BLOCKED_NAMES = {".env", "id_rsa", "id_ed25519", "authorized_keys", "known_hosts"}
BLOCKED_SUFFIXES = {".pem", ".key", ".p12", ".pfx"}
MAX_TEXT_BYTES = 1_000_000
MAX_LIST = 400


def relative_of(root: Path, path: Path) -> str:
    relative = str(path.relative_to(root)).replace("\\", "/")
    return "" if relative == "." else relative


def resolve_workspace_path(root: Path, relative: str) -> Path:
    cleaned = (relative or "").replace("\\", "/").strip()
    if cleaned in {"", ".", "/"}:
        candidate = root
    else:
        if cleaned.startswith("/"):
            raise ValueError("路径无效")
        candidate = root / cleaned
    return resolve_inside(root, candidate)


def is_blocked(root: Path, path: Path) -> bool:
    relative = relative_of(root, path)
    parts = Path(relative).parts if relative else ()
    if any(part in BLOCKED_PARTS for part in parts):
        return True
    name = path.name.lower()
    if name in BLOCKED_NAMES:
        return True
    return any(name.endswith(suffix) for suffix in BLOCKED_SUFFIXES)


def is_text_file(path: Path) -> bool:
    suffix = path.suffix.lower()
    if path.name.lower() in {".gitignore", ".dockerignore", "dockerfile", "makefile", "license", "readme"}:
        return True
    if suffix in TEXT_EXTS:
        return True
    if suffix:
        return False
    try:
        sample = path.read_bytes()[:4096]
    except OSError:
        return False
    if b"\x00" in sample:
        return False
    try:
        sample.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return True


def list_dir(root: Path, relative: str) -> dict[str, Any]:
    folder = resolve_workspace_path(root, relative)
    if not folder.exists():
        raise FileNotFoundError("目录不存在")
    if not folder.is_dir():
        raise NotADirectoryError("不是目录")
    if is_blocked(root, folder):
        raise PermissionError("该路径不可访问")

    items: list[dict[str, Any]] = []
    try:
        entries = list(folder.iterdir())
    except OSError as exc:
        raise PermissionError(str(exc)) from exc

    entries.sort(key=lambda item: (not item.is_dir(), item.name.lower()))
    for entry in entries[:MAX_LIST]:
        if is_blocked(root, entry):
            continue
        try:
            stat = entry.stat()
        except OSError:
            continue
        kind = "dir" if entry.is_dir() else "file"
        text = kind == "file" and is_text_file(entry)
        items.append(
            {
                "name": entry.name,
                "path": relative_of(root, entry),
                "kind": kind,
                "size": stat.st_size if kind == "file" else 0,
                "mtime": int(stat.st_mtime),
                "text": text,
            }
        )

    parent = "" if folder == root else relative_of(root, folder.parent)
    return {
        "root": str(root),
        "path": relative_of(root, folder),
        "parent": parent,
        "items": items,
    }


def read_text(root: Path, relative: str) -> dict[str, Any]:
    path = resolve_workspace_path(root, relative)
    if not path.is_file():
        raise FileNotFoundError("文件不存在")
    if is_blocked(root, path):
        raise PermissionError("该文件不可访问")
    if path.stat().st_size > MAX_TEXT_BYTES:
        raise ValueError("文件超过 1MB，请下载后查看")
    if not is_text_file(path):
        raise ValueError("不是可编辑的文本文件")
    content = path.read_text(encoding="utf-8", errors="replace")
    return {"path": relative_of(root, path), "name": path.name, "content": content, "size": path.stat().st_size}


def write_text(root: Path, relative: str, content: str) -> dict[str, Any]:
    path = resolve_workspace_path(root, relative)
    if is_blocked(root, path):
        raise PermissionError("该文件不可写入")
    if not is_text_file(path) and path.exists():
        raise ValueError("不是可编辑的文本文件")
    if not path.exists():
        raise FileNotFoundError("文件不存在")
    data = content.encode("utf-8")
    if len(data) > MAX_TEXT_BYTES:
        raise ValueError("内容超过 1MB")
    path.write_text(content, encoding="utf-8")
    return {"ok": True, "path": relative_of(root, path), "size": path.stat().st_size}


def download_path(root: Path, relative: str) -> Path:
    path = resolve_workspace_path(root, relative)
    if not path.is_file():
        raise FileNotFoundError("文件不存在")
    if is_blocked(root, path):
        raise PermissionError("该文件不可下载")
    return path
