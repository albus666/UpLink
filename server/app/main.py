from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Annotated, Any, Callable

from fastapi import Depends, FastAPI, File, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from .agent_runner import AgentRunner
from .auth import extract_bearer, token_matches
from .config import Settings, load_settings
from .db import Store
from .git_ops import GitError, commit as git_commit
from .git_ops import is_git_repo
from .git_ops import pull as git_pull
from .git_ops import push as git_push
from .git_ops import status as git_status
from .paths import sanitize_filename


class AppState:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.store = Store(settings.db_path)
        self.runner = AgentRunner(self.store, settings)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = load_settings()
    state = AppState(settings)
    state.runner.start()
    app.state.pilot = state
    yield
    await state.runner.shutdown()


app = FastAPI(title="uplink", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


def get_state() -> AppState:
    return app.state.pilot


def require_user(
    state: Annotated[AppState, Depends(get_state)],
    authorization: Annotated[str | None, Header()] = None,
) -> str:
    token = extract_bearer(authorization)
    if not token_matches(token, state.settings.app_token):
        raise HTTPException(status_code=401, detail="口令错误")
    return token


Auth = Annotated[str, Depends(require_user)]
State = Annotated[AppState, Depends(get_state)]


class LoginBody(BaseModel):
    token: str


class TaskBody(BaseModel):
    prompt: str = Field(min_length=1, max_length=20000)
    upload_ids: list[str] = Field(default_factory=list)
    resume: bool = False
    session_id: str | None = None


class CommitBody(BaseModel):
    message: str = Field(min_length=1, max_length=200)


@app.get("/api/health")
def health() -> dict[str, Any]:
    return {"ok": True, "name": "uplink", "time": datetime.now(timezone.utc).isoformat()}


@app.post("/api/auth/login")
def login(body: LoginBody, state: State) -> dict[str, Any]:
    if not token_matches(body.token.strip(), state.settings.app_token):
        raise HTTPException(status_code=401, detail="口令错误")
    return {"ok": True, "token": body.token.strip()}


@app.get("/api/workspace")
def workspace(state: State, _: Auth) -> dict[str, Any]:
    settings = state.settings
    info: dict[str, Any] = {
        "path": str(settings.workspace),
        "exists": settings.workspace.exists(),
        "agent_bin": settings.agent_bin,
        "model": settings.agent_model,
        "git": None,
    }
    if is_git_repo(settings.workspace):
        try:
            info["git"] = git_status(settings.workspace)
        except GitError as exc:
            info["git_error"] = str(exc)
    return info


@app.get("/api/tasks")
def list_tasks(state: State, _: Auth) -> dict[str, Any]:
    return {"items": state.store.list_tasks()}


@app.post("/api/tasks")
async def create_task(body: TaskBody, state: State, _: Auth) -> dict[str, Any]:
    prompt = body.prompt.strip()
    if not prompt:
        raise HTTPException(status_code=400, detail="任务内容不能为空")

    uploads = state.store.get_uploads(body.upload_ids)
    if body.upload_ids and len(uploads) != len(set(body.upload_ids)):
        raise HTTPException(status_code=400, detail="有文件编号不存在")
    if uploads:
        lines = "\n".join(
            f"- {item['relative_path']}（原名 {item['original_name']}）" for item in uploads
        )
        prompt = f"{prompt}\n\n刚上传到工作区的文件：\n{lines}\n请按任务处理这些文件。"

    resume_of = None
    if body.resume:
        resume_of = body.session_id or state.store.latest_session_id()
        if not resume_of:
            raise HTTPException(status_code=400, detail="还没有可续跑的会话")

    task = state.store.create_task(prompt, resume_of=resume_of)
    await state.runner.enqueue(task["id"])
    return task


@app.get("/api/tasks/{task_id}")
def get_task(task_id: str, state: State, _: Auth) -> dict[str, Any]:
    task = state.store.get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return task


@app.post("/api/tasks/{task_id}/cancel")
async def cancel_task(task_id: str, state: State, _: Auth) -> dict[str, Any]:
    task = state.store.get_task(task_id, include_logs=False)
    if task is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    ok = await state.runner.cancel(task_id)
    if not ok and task["status"] in {"succeeded", "failed", "cancelled"}:
        raise HTTPException(status_code=400, detail="任务已经结束")
    if not ok:
        raise HTTPException(status_code=409, detail="当前无法取消该任务")
    return {"ok": True}


@app.post("/api/uploads")
async def upload_file(
    state: State,
    _: Auth,
    file: UploadFile = File(...),
) -> dict[str, Any]:
    settings = state.settings
    original = file.filename or "file"
    safe_name = sanitize_filename(original)
    day = datetime.now(timezone.utc).strftime("%Y%m%d")
    dest_dir = settings.upload_dir / day
    dest_dir.mkdir(parents=True, exist_ok=True)

    max_bytes = settings.max_upload_mb * 1024 * 1024
    dest = dest_dir / f"{datetime.now(timezone.utc).strftime('%H%M%S')}_{safe_name}"
    size = 0
    try:
        with dest.open("wb") as handle:
            while True:
                chunk = await file.read(64 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                if size > max_bytes:
                    raise HTTPException(status_code=413, detail=f"文件超过 {settings.max_upload_mb}MB")
                handle.write(chunk)
    except HTTPException:
        if dest.exists():
            dest.unlink()
        raise
    finally:
        await file.close()

    if size == 0:
        dest.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail="空文件")

    relative = str(dest.relative_to(settings.workspace)).replace("\\", "/")
    return state.store.add_upload(original, dest.name, relative, size)


@app.get("/api/uploads")
def list_uploads(state: State, _: Auth) -> dict[str, Any]:
    return {"items": state.store.list_uploads()}


@app.get("/api/git")
def get_git(state: State, _: Auth) -> dict[str, Any]:
    return _git_call(lambda: git_status(state.settings.workspace))


@app.post("/api/git/pull")
def pull_repo(state: State, _: Auth) -> dict[str, Any]:
    return _git_call(lambda: git_pull(state.settings.workspace))


@app.post("/api/git/commit")
def commit_repo(body: CommitBody, state: State, _: Auth) -> dict[str, Any]:
    return _git_call(lambda: git_commit(state.settings.workspace, body.message))


@app.post("/api/git/push")
def push_repo(state: State, _: Auth) -> dict[str, Any]:
    return _git_call(lambda: git_push(state.settings.workspace))


def _git_call(fn: Callable[[], dict[str, Any]]) -> dict[str, Any]:
    try:
        return fn()
    except GitError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
