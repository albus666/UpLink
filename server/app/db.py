from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class Store:
    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        return conn

    def _init(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS tasks (
                    id TEXT PRIMARY KEY,
                    prompt TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    started_at TEXT,
                    finished_at TEXT,
                    session_id TEXT,
                    resume_of TEXT,
                    result_text TEXT,
                    error TEXT,
                    logs_json TEXT NOT NULL DEFAULT '[]'
                );
                CREATE TABLE IF NOT EXISTS uploads (
                    id TEXT PRIMARY KEY,
                    original_name TEXT NOT NULL,
                    stored_name TEXT NOT NULL,
                    relative_path TEXT NOT NULL,
                    size INTEGER NOT NULL,
                    created_at TEXT NOT NULL
                );
                """
            )
            cols = {row[1] for row in conn.execute("PRAGMA table_info(tasks)").fetchall()}
            if "mode" not in cols:
                conn.execute("ALTER TABLE tasks ADD COLUMN mode TEXT NOT NULL DEFAULT 'agent'")
            if "title" not in cols:
                conn.execute("ALTER TABLE tasks ADD COLUMN title TEXT")
            if "pinned" not in cols:
                conn.execute("ALTER TABLE tasks ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0")
            if "pending_approval_json" not in cols:
                conn.execute("ALTER TABLE tasks ADD COLUMN pending_approval_json TEXT")

    def create_task(self, prompt: str, resume_of: str | None = None, mode: str = "agent") -> dict[str, Any]:
        mode = "ask" if mode == "ask" else "agent"
        task = {
            "id": uuid4().hex[:12],
            "prompt": prompt,
            "status": "queued",
            "created_at": utc_now(),
            "started_at": None,
            "finished_at": None,
            "session_id": None,
            "resume_of": resume_of,
            "result_text": None,
            "error": None,
            "mode": mode,
            "logs": [],
        }
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO tasks (
                    id, prompt, status, created_at, resume_of, mode, logs_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (task["id"], prompt, "queued", task["created_at"], resume_of, mode, "[]"),
            )
        return task

    def list_tasks(self, limit: int = 200) -> list[dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM tasks ORDER BY created_at DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [self._task_from_row(row, include_logs=False) for row in rows]

    def get_task(self, task_id: str, include_logs: bool = True) -> dict[str, Any] | None:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
        if row is None:
            return None
        return self._task_from_row(row, include_logs=include_logs)

    def latest_session_id(self) -> str | None:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT session_id FROM tasks
                WHERE session_id IS NOT NULL AND session_id != ''
                ORDER BY created_at DESC LIMIT 1
                """
            ).fetchone()
        return row["session_id"] if row else None

    def has_active_task(self) -> bool:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT 1 FROM tasks
                WHERE status IN ('queued', 'running', 'awaiting_approval')
                LIMIT 1
                """
            ).fetchone()
        return row is not None

    def set_pending_approval(self, task_id: str, payload: dict[str, Any]) -> None:
        with self._connect() as conn:
            conn.execute(
                "UPDATE tasks SET pending_approval_json = ? WHERE id = ?",
                (json.dumps(payload, ensure_ascii=False), task_id),
            )

    def clear_pending_approval(self, task_id: str) -> None:
        with self._connect() as conn:
            conn.execute(
                "UPDATE tasks SET pending_approval_json = NULL WHERE id = ?",
                (task_id,),
            )

    def next_queued(self) -> dict[str, Any] | None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM tasks WHERE status = 'queued' ORDER BY created_at ASC LIMIT 1"
            ).fetchone()
        return self._task_from_row(row) if row else None

    def mark_running(self, task_id: str) -> None:
        with self._connect() as conn:
            conn.execute(
                "UPDATE tasks SET status = 'running', started_at = ? WHERE id = ?",
                (utc_now(), task_id),
            )

    def mark_awaiting_approval(self, task_id: str) -> None:
        with self._connect() as conn:
            conn.execute(
                "UPDATE tasks SET status = 'awaiting_approval', finished_at = NULL WHERE id = ?",
                (task_id,),
            )

    def mark_finished(
        self,
        task_id: str,
        status: str,
        result_text: str | None = None,
        error: str | None = None,
        session_id: str | None = None,
    ) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE tasks
                SET status = ?, finished_at = ?, result_text = ?, error = ?,
                    session_id = COALESCE(?, session_id)
                WHERE id = ?
                """,
                (status, utc_now(), result_text, error, session_id, task_id),
            )

    def set_session_id(self, task_id: str, session_id: str) -> None:
        with self._connect() as conn:
            conn.execute(
                "UPDATE tasks SET session_id = ? WHERE id = ?",
                (session_id, task_id),
            )

    def append_log(self, task_id: str, kind: str, text: str) -> None:
        if not text:
            return
        entry = {"ts": utc_now(), "kind": kind, "text": text}
        with self._connect() as conn:
            row = conn.execute("SELECT logs_json FROM tasks WHERE id = ?", (task_id,)).fetchone()
            if row is None:
                return
            logs = json.loads(row["logs_json"] or "[]")
            logs.append(entry)
            # Keep the last 2000 lines so the phone UI stays usable.
            logs = logs[-2000:]
            conn.execute(
                "UPDATE tasks SET logs_json = ? WHERE id = ?",
                (json.dumps(logs, ensure_ascii=False), task_id),
            )

    def add_upload(
        self,
        original_name: str,
        stored_name: str,
        relative_path: str,
        size: int,
    ) -> dict[str, Any]:
        item = {
            "id": uuid4().hex[:12],
            "original_name": original_name,
            "stored_name": stored_name,
            "relative_path": relative_path,
            "size": size,
            "created_at": utc_now(),
        }
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO uploads (
                    id, original_name, stored_name, relative_path, size, created_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    item["id"],
                    original_name,
                    stored_name,
                    relative_path,
                    size,
                    item["created_at"],
                ),
            )
        return item

    def list_uploads(self, limit: int = 50) -> list[dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM uploads ORDER BY created_at DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [dict(row) for row in rows]

    def get_uploads(self, ids: list[str]) -> list[dict[str, Any]]:
        if not ids:
            return []
        placeholders = ",".join("?" * len(ids))
        with self._connect() as conn:
            rows = conn.execute(
                f"SELECT * FROM uploads WHERE id IN ({placeholders})",
                ids,
            ).fetchall()
        return [dict(row) for row in rows]

    def _task_from_row(self, row: sqlite3.Row, include_logs: bool = True) -> dict[str, Any]:
        data = dict(row)
        logs = json.loads(data.pop("logs_json") or "[]")
        pending_raw = data.pop("pending_approval_json", None)
        data["pending_approval"] = json.loads(pending_raw) if pending_raw else None
        data["mode"] = data.get("mode") or "agent"
        title = data.get("title")
        data["title"] = title.strip() if isinstance(title, str) and title.strip() else None
        data["pinned"] = bool(data.get("pinned"))
        if include_logs:
            data["logs"] = logs
        else:
            data["log_count"] = len(logs)
        return data

    def thread_bundle(self, thread_id: str) -> tuple[str, list[str]] | None:
        tasks = self.list_tasks(limit=500)
        buckets = _group_thread_ids(tasks)
        if thread_id in buckets:
            return thread_id, buckets[thread_id]
        for root, ids in buckets.items():
            if thread_id in ids:
                return root, ids
        return None

    def update_thread(self, thread_id: str, title: str | None = None, pinned: bool | None = None) -> dict[str, Any] | None:
        bundle = self.thread_bundle(thread_id)
        if bundle is None:
            return None
        root_id, _ids = bundle
        assignments: list[str] = []
        values: list[Any] = []
        if title is not None:
            cleaned = title.strip()
            assignments.append("title = ?")
            values.append(cleaned or None)
        if pinned is not None:
            assignments.append("pinned = ?")
            values.append(1 if pinned else 0)
        if not assignments:
            return self.get_task(root_id, include_logs=False)
        values.append(root_id)
        with self._connect() as conn:
            conn.execute(f"UPDATE tasks SET {', '.join(assignments)} WHERE id = ?", values)
        return self.get_task(root_id, include_logs=False)

    def delete_thread(self, thread_id: str) -> int:
        bundle = self.thread_bundle(thread_id)
        if bundle is None:
            return 0
        _root, ids = bundle
        placeholders = ",".join("?" * len(ids))
        with self._connect() as conn:
            conn.execute(f"DELETE FROM tasks WHERE id IN ({placeholders})", ids)
        return len(ids)


def _group_thread_ids(tasks: list[dict[str, Any]]) -> dict[str, list[str]]:
    by_session: dict[str, dict[str, Any]] = {}
    for task in tasks:
        session_id = task.get("session_id")
        if session_id:
            by_session[str(session_id)] = task

    def root_id(task: dict[str, Any]) -> str:
        current = task
        seen: set[str] = set()
        while current.get("resume_of"):
            ident = str(current.get("id") or "")
            if not ident or ident in seen:
                break
            seen.add(ident)
            previous = by_session.get(str(current.get("resume_of")))
            if previous is None:
                break
            current = previous
        return str(current.get("id") or "")

    buckets: dict[str, list[str]] = {}
    ordered = sorted(tasks, key=lambda item: str(item.get("created_at") or ""))
    for task in ordered:
        ident = root_id(task)
        if not ident:
            continue
        buckets.setdefault(ident, []).append(str(task["id"]))
    return buckets
