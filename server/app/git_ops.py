from __future__ import annotations

import subprocess
from pathlib import Path


class GitError(RuntimeError):
    pass


def is_git_repo(workspace: Path) -> bool:
    return (workspace / ".git").exists() or _run_ok(workspace, ["rev-parse", "--is-inside-work-tree"])


def status(workspace: Path) -> dict:
    _ensure_repo(workspace)
    branch = _run_text(workspace, ["rev-parse", "--abbrev-ref", "HEAD"]).strip()
    porcelain = _run_text(workspace, ["status", "--porcelain=v1"])
    last = _run_text(workspace, ["log", "-1", "--pretty=format:%h %s", "--date=iso"])
    remote = _run_text(workspace, ["remote", "get-url", "origin"], check=False).strip()
    dirty_files = [line[3:] for line in porcelain.splitlines() if line.strip()]
    return {
        "branch": branch,
        "dirty": bool(dirty_files),
        "dirty_files": dirty_files[:80],
        "last_commit": last.strip(),
        "remote": remote,
    }


def pull(workspace: Path) -> dict:
    _ensure_repo(workspace)
    output = _run_text(workspace, ["pull", "--ff-only"])
    return {"ok": True, "output": output, **status(workspace)}


def commit(workspace: Path, message: str) -> dict:
    _ensure_repo(workspace)
    cleaned = " ".join(message.split()).strip()
    if not cleaned:
        raise GitError("提交说明不能为空")
    if len(cleaned) > 200:
        raise GitError("提交说明过长")
    add_out = _run_text(workspace, ["add", "-A"])
    staged = _run_text(workspace, ["diff", "--cached", "--name-only"]).strip()
    if not staged:
        raise GitError("没有可提交的变更")
    commit_out = _run_text(workspace, ["commit", "-m", cleaned])
    return {
        "ok": True,
        "output": "\n".join(part for part in (add_out, commit_out) if part).strip(),
        **status(workspace),
    }


def push(workspace: Path) -> dict:
    _ensure_repo(workspace)
    output = _run_text(workspace, ["push"])
    return {"ok": True, "output": output, **status(workspace)}


def _ensure_repo(workspace: Path) -> None:
    if not is_git_repo(workspace):
        raise GitError(f"工作区不是 git 仓库：{workspace}")


def _run_ok(workspace: Path, args: list[str]) -> bool:
    try:
        _run_text(workspace, args)
        return True
    except GitError:
        return False


def _run_text(workspace: Path, args: list[str], check: bool = True) -> str:
    try:
        completed = subprocess.run(
            ["git", *args],
            cwd=workspace,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
    except FileNotFoundError as exc:
        raise GitError("服务器未安装 git") from exc
    except subprocess.TimeoutExpired as exc:
        raise GitError("git 命令超时") from exc
    output = ((completed.stdout or "") + (completed.stderr or "")).strip()
    if check and completed.returncode != 0:
        raise GitError(output or f"git {' '.join(args)} 失败")
    return output
