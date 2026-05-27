import json
from pathlib import Path
from typing import Any, Optional

SPECWORK = Path(".specwork")


def _ensure_dir(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)


def load_state(slug: str) -> Optional[dict[str, Any]]:
    path = SPECWORK / "_state" / f"{slug}-state.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def save_state(slug: str, data: dict[str, Any]):
    path = SPECWORK / "_state" / f"{slug}-state.json"
    _ensure_dir(path)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def load_rules(slug: str) -> Optional[dict[str, Any]]:
    path = SPECWORK / "_state" / f"{slug}-rules.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def save_rules(slug: str, data: dict[str, Any]):
    path = SPECWORK / "_state" / f"{slug}-rules.json"
    _ensure_dir(path)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def load_cache(slug: str) -> Optional[dict[str, Any]]:
    path = SPECWORK / "_state" / f"{slug}-implementation-cache.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def save_cache(slug: str, data: dict[str, Any]):
    path = SPECWORK / "_state" / f"{slug}-implementation-cache.json"
    _ensure_dir(path)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def load_plan(slug: str) -> Optional[list[dict[str, Any]]]:
    path = SPECWORK / "_plan" / f"{slug}-plan.json"
    if not path.exists():
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    return data.get("target_files", [])


def save_plan(slug: str, target_files: list[dict[str, Any]]):
    path = SPECWORK / "_plan" / f"{slug}-plan.json"
    _ensure_dir(path)
    path.write_text(
        json.dumps({"schema_version": 1, "id": slug, "target_files": target_files}, indent=2) + "\n",
        encoding="utf-8"
    )


def load_spec(slug: str) -> Optional[str]:
    path = SPECWORK / "_spec" / f"{slug}-spec.md"
    if not path.exists():
        return None
    return path.read_text(encoding="utf-8")


def load_source(slug: str) -> Optional[str]:
    path = SPECWORK / "_spec" / f"{slug}-source.md"
    if not path.exists():
        return None
    return path.read_text(encoding="utf-8")
