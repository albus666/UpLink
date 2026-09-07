from pathlib import Path
import re


SAFE_NAME = re.compile(r"[^A-Za-z0-9._-]+")


def sanitize_filename(name: str | None) -> str:
    raw = Path(name or "file").name
    cleaned = SAFE_NAME.sub("_", raw).strip("._") or "file"
    return cleaned[:120]


def resolve_inside(root: Path, candidate: Path) -> Path:
    resolved = candidate.resolve()
    root_resolved = root.resolve()
    if resolved != root_resolved and root_resolved not in resolved.parents:
        raise ValueError("路径超出工作区")
    return resolved
