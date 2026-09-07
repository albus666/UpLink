from __future__ import annotations

import asyncio
import json
import os
import signal
from typing import Any

from .config import Settings
from .db import Store


PROMPT_PREFIX = """你在一台服务器的本地工作区里执行任务。手机只是 Uplink 客户端，真正改文件、跑命令的是你。

工作区绝对路径：{workspace}

硬性规则：
- 只修改工作区以内的文件，不要碰系统目录
- 不要使用 sudo，不要改 nginx / systemd / 防火墙 / SSH 配置
- 不要读取或输出密钥、token、.env、私钥
- 除非用户明确要求，否则不要 git push
- 回复用中文，简洁说明你改了什么

用户任务：
{prompt}
"""


class AgentRunner:
    def __init__(self, store: Store, settings: Settings) -> None:
        self.store = store
        self.settings = settings
        self._queue = asyncio.Queue[str]()
        self._worker: asyncio.Task[None] | None = None
        self._current_proc: asyncio.subprocess.Process | None = None
        self._current_task_id: str | None = None
        self._cancel_requested = False

    def start(self) -> None:
        if self._worker is None:
            self._worker = asyncio.create_task(self._loop(), name="agent-worker")

    async def shutdown(self) -> None:
        if self._current_task_id:
            await self.cancel(self._current_task_id)
        if self._worker:
            self._worker.cancel()
            try:
                await self._worker
            except asyncio.CancelledError:
                pass

    async def enqueue(self, task_id: str) -> None:
        await self._queue.put(task_id)

    async def cancel(self, task_id: str) -> bool:
        task = self.store.get_task(task_id, include_logs=False)
        if task is None:
            return False
        if task["status"] == "queued":
            self.store.mark_finished(task_id, "cancelled", error="已取消")
            self.store.append_log(task_id, "system", "任务在排队时被取消")
            return True
        if self._current_task_id != task_id or self._current_proc is None:
            return False
        self._cancel_requested = True
        self.store.append_log(task_id, "system", "正在停止 Agent…")
        _stop_process(self._current_proc)
        return True

    async def _loop(self) -> None:
        while True:
            task_id = await self._queue.get()
            task = self.store.get_task(task_id)
            if task is None or task["status"] != "queued":
                continue
            try:
                await self._run(task)
            except Exception as exc:  # noqa: BLE001 - isolate worker
                self.store.append_log(task_id, "error", f"运行器异常：{exc}")
                self.store.mark_finished(task_id, "failed", error=str(exc))
            finally:
                self._current_proc = None
                self._current_task_id = None
                self._cancel_requested = False

    async def _run(self, task: dict[str, Any]) -> None:
        task_id = task["id"]
        self._current_task_id = task_id
        self.store.mark_running(task_id)
        self.store.append_log(task_id, "system", "开始调用 Cursor Agent")

        prompt = PROMPT_PREFIX.format(
            workspace=self.settings.workspace,
            prompt=task["prompt"],
        )
        cmd = [
            self.settings.agent_bin,
            "-p",
            "--force",
            "--trust",
            "--workspace",
            str(self.settings.workspace),
            "--output-format",
            "stream-json",
        ]
        if self.settings.agent_model:
            cmd.extend(["--model", self.settings.agent_model])
        resume = task.get("resume_of") or None
        if resume:
            cmd.extend(["--resume", resume])
            self.store.append_log(task_id, "system", f"续跑会话 {resume}")
        cmd.append(prompt)

        env = os.environ.copy()
        if self.settings.cursor_api_key:
            env["CURSOR_API_KEY"] = self.settings.cursor_api_key

        kwargs: dict[str, Any] = {}
        if os.name != "nt":
            kwargs["start_new_session"] = True

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=self.settings.workspace,
                env=env,
                **kwargs,
            )
        except FileNotFoundError:
            message = (
                f"找不到命令 `{self.settings.agent_bin}`。"
                "请在服务器安装 Cursor CLI：curl https://cursor.com/install -fsS | bash"
            )
            self.store.append_log(task_id, "error", message)
            self.store.mark_finished(task_id, "failed", error=message)
            return

        self._current_proc = proc
        session_id: str | None = None
        result_text = ""
        stderr_buf = ""

        async def read_stderr() -> None:
            nonlocal stderr_buf
            assert proc.stderr is not None
            while True:
                chunk = await proc.stderr.readline()
                if not chunk:
                    break
                line = chunk.decode("utf-8", errors="replace").rstrip()
                if line:
                    stderr_buf += line + "\n"
                    self.store.append_log(task_id, "stderr", line)

        stderr_task = asyncio.create_task(read_stderr())
        assert proc.stdout is not None
        assistant_bits: list[str] = []

        try:
            while True:
                raw = await asyncio.wait_for(
                    proc.stdout.readline(),
                    timeout=self.settings.agent_timeout_sec,
                )
                if not raw:
                    break
                line = raw.decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                event = _parse_event(line)
                if event is None:
                    self.store.append_log(task_id, "raw", line)
                    continue
                kind, text, extra = _format_event(event)
                if extra.get("session_id") and not session_id:
                    session_id = str(extra["session_id"])
                    self.store.set_session_id(task_id, session_id)
                if extra.get("result"):
                    result_text = str(extra["result"])
                if kind == "assistant":
                    assistant_bits.append(text)
                if text:
                    self.store.append_log(task_id, kind, text)
        except asyncio.TimeoutError:
            _stop_process(proc)
            self.store.append_log(task_id, "error", "Agent 超时，已停止")
            self.store.mark_finished(task_id, "failed", error="Agent 超时")
            await _wait_silent(proc)
            await _wait_silent_task(stderr_task)
            return

        await _wait_silent_task(stderr_task)
        code = await proc.wait()

        if self._cancel_requested:
            self.store.mark_finished(task_id, "cancelled", error="已取消", session_id=session_id)
            return

        if not result_text:
            result_text = "".join(assistant_bits).strip()
        if code != 0:
            error = (stderr_buf.strip() or f"Agent 退出码 {code}")[:2000]
            self.store.append_log(task_id, "error", error)
            self.store.mark_finished(task_id, "failed", result_text=result_text, error=error, session_id=session_id)
            return

        self.store.append_log(task_id, "system", "任务完成")
        self.store.mark_finished(
            task_id,
            "succeeded",
            result_text=result_text,
            session_id=session_id,
        )


def _parse_event(line: str) -> dict[str, Any] | None:
    try:
        data = json.loads(line)
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def _format_event(event: dict[str, Any]) -> tuple[str, str, dict[str, Any]]:
    extra: dict[str, Any] = {}
    session_id = event.get("session_id")
    if session_id:
        extra["session_id"] = session_id

    etype = event.get("type")
    subtype = event.get("subtype")

    if etype == "system" and subtype == "init":
        model = event.get("model") or "unknown"
        extra["session_id"] = event.get("session_id") or session_id
        return "system", f"Agent 已启动，模型 {model}", extra

    if etype == "assistant":
        # Skip buffered duplicate flushes emitted by stream-partial-output.
        if event.get("model_call_id") is not None:
            return "assistant", "", extra
        text = _message_text(event.get("message"))
        return "assistant", text, extra

    if etype == "tool_call":
        label = _tool_label(event.get("tool_call") or {})
        verb = "开始" if subtype == "started" else "完成"
        return "tool", f"{verb} {label}", extra

    if etype == "result":
        result = event.get("result") or ""
        extra["result"] = result
        duration = event.get("duration_ms")
        suffix = f"（{duration}ms）" if duration else ""
        return "system", f"Agent 结束{suffix}", extra

    if etype == "user":
        return "system", "", extra

    return "raw", json.dumps(event, ensure_ascii=False)[:500], extra


def _message_text(message: Any) -> str:
    if not isinstance(message, dict):
        return ""
    content = message.get("content") or []
    parts: list[str] = []
    for block in content:
        if isinstance(block, dict) and block.get("type") == "text":
            parts.append(str(block.get("text") or ""))
    return "".join(parts)


def _tool_label(tool_call: dict[str, Any]) -> str:
    mapping = {
        "readToolCall": "读取",
        "writeToolCall": "写入",
        "editToolCall": "编辑",
        "applyPatchToolCall": "打补丁",
        "shellToolCall": "命令",
        "grepToolCall": "搜索",
        "globToolCall": "匹配文件",
        "lsToolCall": "列出目录",
        "deleteToolCall": "删除",
    }
    for key, verb in mapping.items():
        if key in tool_call:
            args = (tool_call[key] or {}).get("args") or {}
            target = args.get("path") or args.get("command") or args.get("query") or ""
            return f"{verb} {target}".strip()
    func = tool_call.get("function") or {}
    if func:
        return str(func.get("name") or "工具")
    keys = [key for key in tool_call.keys() if key.endswith("ToolCall")]
    return keys[0] if keys else "工具调用"


def _stop_process(proc: asyncio.subprocess.Process) -> None:
    if proc.returncode is not None:
        return
    try:
        if os.name != "nt" and proc.pid:
            os.killpg(proc.pid, signal.SIGTERM)
        else:
            proc.terminate()
    except ProcessLookupError:
        return
    except OSError:
        proc.kill()


async def _wait_silent(proc: asyncio.subprocess.Process) -> None:
    try:
        await asyncio.wait_for(proc.wait(), timeout=8)
    except asyncio.TimeoutError:
        try:
            proc.kill()
        except OSError:
            pass


async def _wait_silent_task(task: asyncio.Task[None]) -> None:
    try:
        await asyncio.wait_for(task, timeout=2)
    except (asyncio.TimeoutError, asyncio.CancelledError):
        task.cancel()
