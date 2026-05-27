from __future__ import annotations

import json
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional

from engine import router
from engine.persistence import SPECWORK


@dataclass
class PipelineState:
    slug: str
    ticket: Optional[str] = None
    ticket_type: str = "feature"
    complexity: str = "MEDIUM"
    branch: str = ""
    base_branch: str = ""
    current_step: str = "start"
    step_index: int = 0
    retries: int = 0
    max_retries: int = 2
    spec_file: str = ""
    plan_file: str = ""
    source_file: str = ""
    rules_file: str = ""
    cache_file: str = ""
    path_file: str = ""
    metrics_mode: str = "none"
    schema_version: int = 1
    spec_write_timestamp: int = 0
    escalations: list = field(default_factory=list)
    extra: dict = field(default_factory=dict)  # unknown on-disk keys, preserved on save

    @property
    def spec_path(self) -> Path:
        return SPECWORK / "_spec" / f"{self.slug}-spec.md"

    @property
    def plan_json_path(self) -> Path:
        return SPECWORK / "_plan" / f"{self.slug}-plan.json"

    @property
    def plan_md_path(self) -> Path:
        return SPECWORK / "_plan" / f"{self.slug}-plan.md"

    @property
    def state_path(self) -> Path:
        return SPECWORK / "_state" / f"{self.slug}-state.json"

    @property
    def rules_path(self) -> Path:
        return SPECWORK / "_state" / f"{self.slug}-rules.json"

    @property
    def cache_path(self) -> Path:
        return SPECWORK / "_state" / f"{self.slug}-implementation-cache.json"

    @property
    def source_path(self) -> Path:
        return SPECWORK / "_spec" / f"{self.slug}-source.md"

    @property
    def path_path(self) -> Path:
        return SPECWORK / "_state" / f"{self.slug}-path.json"

    def next_step(self) -> str:
        return router.next_step(self.ticket_type, self.current_step, self.retries, self.max_retries)

    def should_retry(self) -> bool:
        return self.retries < self.max_retries

    def escalate(self, reason: str):
        self.escalations.append({"reason": reason, "attempts": self.retries})
        self.retries = self.max_retries

    def to_dict(self) -> dict:
        d = asdict(self)
        # Re-merge on-disk keys this dataclass doesn't model (e.g. "id",
        # "input_type", "source_title") so saving never drops them; core fields win.
        extra = d.pop("extra", {})
        merged = dict(extra)
        merged.update(d)
        return merged

    @classmethod
    def from_dict(cls, data: dict) -> PipelineState:
        data = dict(data)  # copy so we don't mutate the caller's dict
        # The implementation cache lives in its own file (see persistence.save_cache),
        # never in state.json. Drop any stray "cache" key so it doesn't leak into extra.
        data.pop("cache", None)
        from dataclasses import fields
        valid = {f.name for f in fields(cls)}
        # preserve "slug" (canonical) but accept "id" as legacy fallback
        if "slug" not in data and "id" in data:
            data["slug"] = data["id"]
        clean = {k: v for k, v in data.items() if k in valid and k != "extra"}
        extra = {k: v for k, v in data.items() if k not in valid}
        inst = cls(**clean)
        inst.extra = extra
        return inst


def load_pipeline_state(slug: str) -> Optional[PipelineState]:
    path = SPECWORK / "_state" / f"{slug}-state.json"
    if not path.exists():
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    return PipelineState.from_dict(data)


def save_pipeline_state(state: PipelineState):
    state.state_path.parent.mkdir(parents=True, exist_ok=True)
    state.state_path.write_text(
        json.dumps(state.to_dict(), indent=2) + "\n", encoding="utf-8"
    )
