from __future__ import annotations

import asyncio
import re
import time
from typing import Any

from .config import Settings

FALLBACK_MODELS: list[dict[str, str]] = [
    {"id": "auto", "label": "Auto"},
    {"id": "composer-2.5", "label": "Composer 2.5"},
    {"id": "composer-2.5-fast", "label": "Composer 2.5 Fast"},
    {"id": "cursor-grok-4.6-low", "label": "Cursor Grok 4.6 Low"},
    {"id": "cursor-grok-4.6-low-fast", "label": "Cursor Grok 4.6 Low Fast"},
    {"id": "cursor-grok-4.6-medium", "label": "Cursor Grok 4.6 Medium"},
    {"id": "cursor-grok-4.6-medium-fast", "label": "Cursor Grok 4.6 Medium Fast"},
    {"id": "cursor-grok-4.6-high", "label": "Cursor Grok 4.6"},
    {"id": "cursor-grok-4.6-high-fast", "label": "Cursor Grok 4.6 Fast"},
    {"id": "cursor-grok-4.6-xhigh", "label": "Cursor Grok 4.6 Extra High"},
    {"id": "cursor-grok-4.6-xhigh-fast", "label": "Cursor Grok 4.6 Extra High Fast"},
    {"id": "gpt-5.3-codex", "label": "Codex 5.3"},
    {"id": "gpt-5.3-codex-high", "label": "Codex 5.3 High"},
    {"id": "gpt-5.3-codex-high-fast", "label": "Codex 5.3 High Fast"},
    {"id": "claude-sonnet-5-thinking-low", "label": "Claude Sonnet 5 Low Thinking"},
    {"id": "claude-sonnet-5-thinking-medium", "label": "Claude Sonnet 5 Medium Thinking"},
    {"id": "claude-sonnet-5-thinking-high", "label": "Claude Sonnet 5 Thinking"},
    {"id": "claude-opus-5-thinking-high", "label": "Claude Opus 5 Thinking"},
]

_ID = re.compile(r"^[A-Za-z0-9._-]+$")
_TAG = re.compile(r"\s*\((?:current|default)\)\s*", re.I)


def parse_model_list(text: str) -> list[dict[str, str]]:
    items: list[dict[str, str]] = []
    seen: set[str] = set()
    for raw in text.splitlines():
        line = raw.strip()
        if " - " not in line:
            continue
        ident, label = line.split(" - ", 1)
        ident = ident.strip()
        label = _TAG.sub("", label).strip() or ident
        if not _ID.fullmatch(ident) or ident in seen:
            continue
        seen.add(ident)
        items.append({"id": ident, "label": label})
    return items


def model_label(model: str, items: list[dict[str, str]]) -> str:
    for item in items:
        if item["id"] == model:
            return item["label"]
    return model or "默认"


class ModelCatalog:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.items = list(FALLBACK_MODELS)
        self._refreshing = False
        self._loaded_at = 0.0

    def snapshot(self) -> list[dict[str, str]]:
        current = self.settings.agent_model
        if current and all(item["id"] != current for item in self.items):
            return [{"id": current, "label": current}, *self.items]
        return list(self.items)

    def start(self) -> None:
        asyncio.create_task(self.refresh())

    async def refresh(self, force: bool = False) -> None:
        if self._refreshing:
            return
        if not force and self._loaded_at and time.monotonic() - self._loaded_at < 600:
            return
        self._refreshing = True
        try:
            proc = await asyncio.create_subprocess_exec(
                self.settings.agent_bin,
                "--list-models",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            out, _ = await asyncio.wait_for(proc.communicate(), timeout=45)
            parsed = parse_model_list(out.decode("utf-8", errors="replace"))
            if parsed:
                self.items = parsed
                self._loaded_at = time.monotonic()
        except Exception:  # noqa: BLE001 - keep fallback catalog
            pass
        finally:
            self._refreshing = False


def workspace_models(catalog: ModelCatalog) -> dict[str, Any]:
    items = catalog.snapshot()
    current = catalog.settings.agent_model
    return {
        "model": current,
        "model_label": model_label(current, items),
        "models": items,
    }
