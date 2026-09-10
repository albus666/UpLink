from __future__ import annotations

import asyncio
import json
import os
import signal
from typing import Any

from .config import Settings
from .db import Store


# stream-json 单行事件可能超过 asyncio 默认 64 KiB 行缓冲。
_STDIO_LINE_LIMIT = 16 * 1024 * 1024

PROMPT_PREFIX = """你在一台服务器的本地工作区里执行任务。手机只是 Uplink 客户端，真正改文件、跑命令的是你。

工作区绝对路径：{workspace}

硬性规则：
- 可修改工作区文件，也可在需要时使用 sudo、改 nginx / systemd / 防火墙 / SSH、读写 .env 与密钥
- 涉及 nginx、systemd、防火墙、SSH、/etc/、.env、.ssh、私钥、token 等敏感操作时，系统会在手机 App 弹窗让用户确认后再继续
- 常规读写与命令无需额外确认，直接执行
- 除非用户明确要求，否则不要 git push
- 回复用中文，简洁说明你改了什么

用户任务：
{prompt}
"""

ASK_PREFIX = """你在一台服务器的本地工作区里回答问题。当前是 Ask 模式。

工作区绝对路径：{workspace}

硬性规则：
- 只阅读和分析，不要修改、创建、删除任何文件
- 不要运行会改动系统或仓库的命令，不要 git commit / push
- 不要读取或输出密钥、token、.env、私钥
- 回复用中文，直接给出结论

用户问题：
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
        if task["status"] in {"succeeded", "failed", "cancelled"}:
            return False
        if task["status"] == "queued":
            self.store.mark_finished(task_id, "cancelled", error="已取消")
            self.store.append_log(task_id, "system", "任务在排队时被取消")
            return True
        if task["status"] == "awaiting_approval":
            self.store.clear_pending_approval(task_id)
            self.store.mark_finished(task_id, "cancelled", error="已取消")
            self.store.append_log(task_id, "system", "等待确认时已取消")
            return True
        if self._current_task_id != task_id:
            return False
        self._cancel_requested = True
        self.store.append_log(task_id, "system", "已停止这一轮")
        proc = self._current_proc
        if proc is not None:
            asyncio.create_task(_ensure_dead(proc))
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
        fresh = self.store.get_task(task_id, include_logs=False)
        if fresh is None or fresh["status"] != "queued":
            return
        self._current_task_id = task_id
        self.store.mark_running(task_id)
        mode = "ask" if (fresh.get("mode") or "agent") == "ask" else "agent"
        if mode == "ask":
            self.store.append_log(task_id, "system", "Ask 模式：只分析，不改文件")
        else:
            self.store.append_log(task_id, "system", "Agent 模式：可以改文件")

        prefix = ASK_PREFIX if mode == "ask" else PROMPT_PREFIX
        prompt = prefix.format(
            workspace=self.settings.workspace,
            prompt=task["prompt"],
        )
        cmd = [
            self.settings.agent_bin,
            "-p",
            "--trust",
            "--workspace",
            str(self.settings.workspace),
            "--output-format",
            "stream-json",
        ]
        if mode == "ask":
            cmd.extend(["--mode", "ask"])
        else:
            cmd.append("--force")
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
                limit=_STDIO_LINE_LIMIT,
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
        if self._cancel_requested:
            await _ensure_dead(proc)
            self.store.mark_finished(task_id, "cancelled", error="已取消")
            return

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
                timeout = 2 if self._cancel_requested else self.settings.agent_timeout_sec
                try:
                    raw = await asyncio.wait_for(proc.stdout.readline(), timeout=timeout)
                except asyncio.LimitOverrunError as exc:
                    self.store.append_log(
                        task_id,
                        "system",
                        f"跳过一条过大的 stream-json 输出（{exc.consumed} 字节）",
                    )
                    try:
                        await proc.stdout.readexactly(exc.consumed)
                    except (asyncio.IncompleteReadError, ValueError):
                        break
                    continue
                except asyncio.TimeoutError:
                    if self._cancel_requested:
                        await _ensure_dead(proc)
                        break
                    _stop_process(proc)
                    self.store.append_log(task_id, "error", "Agent 超时，已停止")
                    self.store.mark_finished(task_id, "failed", error="Agent 超时")
                    await _wait_silent(proc)
                    await _wait_silent_task(stderr_task)
                    return
                if not raw:
                    break
                line = raw.decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                event = _parse_event(line)
                if event is None:
                    self.store.append_log(task_id, "raw", line)
                    continue
                if (
                    mode == "agent"
                    and event.get("type") == "tool_call"
                    and event.get("subtype") == "started"
                ):
                    from .approval import check_tool_call

                    verdict = check_tool_call(event.get("tool_call") or {})
                    if verdict.sensitive:
                        self.store.set_pending_approval(task_id, verdict.to_dict())
                        self.store.append_log(task_id, "approval", verdict.summary)
                        self.store.append_log(task_id, "system", "等待手机 App 确认敏感操作")
                        _stop_process(proc)
                        await _ensure_dead(proc)
                        await _wait_silent_task(stderr_task)
                        self.store.mark_finished(
                            task_id,
                            "awaiting_approval",
                            session_id=session_id,
                        )
                        return
                kind, text, extra = _format_event(event)
                if extra.get("session_id") and not session_id:
                    session_id = str(extra["session_id"])
                    self.store.set_session_id(task_id, session_id)
                if extra.get("result") is not None:
                    result_text = str(extra["result"])
                if extra.get("done"):
                    if text:
                        self.store.append_log(task_id, kind, text)
                    break
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
        if self._cancel_requested:
            await _ensure_dead(proc)
            self.store.mark_finished(task_id, "cancelled", error="已停止", session_id=session_id)
            return

        if result_text or assistant_bits:
            await _ensure_dead(proc)
            if not result_text:
                result_text = "".join(assistant_bits).strip()
            self.store.append_log(task_id, "system", "这一轮完成")
            self.store.mark_finished(
                task_id,
                "succeeded",
                result_text=result_text,
                session_id=session_id,
            )
            return

        try:
            code = await asyncio.wait_for(proc.wait(), timeout=8)
        except asyncio.TimeoutError:
            await _ensure_dead(proc)
            self.store.append_log(task_id, "error", "Agent 进程未退出，已强制结束")
            self.store.mark_finished(task_id, "failed", error="Agent 进程未退出", session_id=session_id)
            return

        if self._cancel_requested:
            self.store.mark_finished(task_id, "cancelled", error="已停止", session_id=session_id)
            return

        if not result_text:
            result_text = "".join(assistant_bits).strip()
        if code != 0:
            error = (stderr_buf.strip() or f"Agent 退出码 {code}")[:2000]
            self.store.append_log(task_id, "error", error)
            self.store.mark_finished(task_id, "failed", result_text=result_text, error=error, session_id=session_id)
            return

        self.store.append_log(task_id, "system", "这一轮完成")
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

    if etype == "thinking":
        if subtype in {"completed", "end", "delta"} and not event.get("text"):
            return "system", "", extra
        text = str(event.get("text") or event.get("thought") or "").strip()
        if not text:
            return "system", "", extra
        return "thought", text[:300], extra

    if etype == "tool_call":
        label = _tool_label(event.get("tool_call") or {})
        verb = "开始" if subtype == "started" else "完成"
        return "tool", f"{verb} {label}", extra

    if etype == "result":
        result = event.get("result") or ""
        extra["result"] = result
        extra["done"] = True
        duration = event.get("duration_ms")
        suffix = f"（{duration}ms）" if duration else ""
        return "system", f"这一轮结束{suffix}", extra

    if etype == "user":
        return "system", "", extra

    return "raw", "", extra


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
        "webSearchToolCall": "搜索网页",
        "webFetchToolCall": "打开网页",
        "mcpToolCall": "MCP",
    }
    for key, verb in mapping.items():
        if key in tool_call:
            args = (tool_call[key] or {}).get("args") or {}
            target = args.get("path") or args.get("command") or args.get("query") or args.get("url") or args.get("searchTerm") or ""
            return f"{verb} {target}".strip()
    func = tool_call.get("function") or {}
    if func:
        return str(func.get("name") or "工具")
    keys = [key for key in tool_call.keys() if key.endswith("ToolCall")]
    if not keys:
        return "工具调用"
    key = keys[0]
    name = key[: -len("ToolCall")]
    pretty = {
        "webSearch": "搜索网页",
        "webFetch": "打开网页",
        "readFile": "读取",
    }.get(name, name)
    return pretty


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


def _kill_process(proc: asyncio.subprocess.Process) -> None:
    if proc.returncode is not None:
        return
    try:
        if os.name != "nt" and proc.pid:
            os.killpg(proc.pid, signal.SIGKILL)
        else:
            proc.kill()
    except ProcessLookupError:
        return
    except OSError:
        try:
            proc.kill()
        except OSError:
            pass


async def _ensure_dead(proc: asyncio.subprocess.Process) -> None:
    _stop_process(proc)
    try:
        await asyncio.wait_for(proc.wait(), timeout=2)
        return
    except asyncio.TimeoutError:
        pass
    _kill_process(proc)
    try:
        await asyncio.wait_for(proc.wait(), timeout=3)
    except asyncio.TimeoutError:
        pass


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
