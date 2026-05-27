import json
import re
from pathlib import Path
from typing import Optional


SPECWORK = Path(".specwork")


def _current_branch() -> Optional[str]:
    """Current git branch, or None if git is unavailable or we're not in a repo.
    Catches FileNotFoundError so the engine degrades gracefully where git is not
    installed."""
    import subprocess
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=5
        )
    except (FileNotFoundError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def resolve_slug() -> Optional[str]:
    branch = _current_branch()
    if not branch:
        return None
    state_dir = SPECWORK / "_state"
    if state_dir.exists():
        for f in sorted(state_dir.glob("*-state.json")):
            try:
                data = json.loads(f.read_text(encoding="utf-8"))
                if data.get("branch") == branch:
                    return data.get("slug", data.get("id", ""))
            except Exception:
                continue
    branch_clean = branch.split("/", 1)[-1] if "/" in branch else branch
    slug = re.sub(r"[^a-z0-9]+", "-", branch_clean.lower()).strip("-")
    return slug


def require_specwork(spec_dir: str = ".specwork") -> Optional[str]:
    """Precondition gate for state-consuming commands. Returns a reject reason
    when the pipeline is not initialized here, else None."""
    root = Path(spec_dir)
    if not root.is_dir():
        return f"No pipeline working directory ({spec_dir}/ not found). Run /f-start first."
    state_dir = root / "_state"
    if not state_dir.is_dir() or not any(state_dir.glob("*-state.json")):
        return f"Pipeline not initialized ({spec_dir}/_state has no *-state.json). Run /f-start first."
    return None


def resolve_state_file() -> Optional[Path]:
    slug = resolve_slug()
    if slug:
        p = SPECWORK / "_state" / f"{slug}-state.json"
        if p.exists():
            return p
    state_dir = SPECWORK / "_state"
    if state_dir.exists():
        files = sorted(state_dir.glob("*-state.json"))
        if files:
            return files[0]
    return None


def check_open_questions(slug: str) -> list[tuple[str, list[str]]]:
    blockers: list[tuple[str, list[str]]] = []
    paths = [
        SPECWORK / "_spec" / f"{slug}-spec.md",
        SPECWORK / "_plan" / f"{slug}-plan.md",
    ]
    for p in paths:
        if not p.exists():
            continue
        text = p.read_text(encoding="utf-8")
        m = re.search(r"(?ms)^## Open Questions\b(.*?)(?=^## |\Z)", text)
        section = m.group(1) if m else ""
        unresolved = [
            l.strip() for l in section.splitlines()
            if re.match(r"^\s*-\s*\[\s*\]", l)
        ]
        if unresolved:
            blockers.append((str(p), unresolved))
    return blockers


def check_plan_staleness(slug: str) -> bool:
    plan_path = SPECWORK / "_plan" / f"{slug}-plan.md"
    state_path = SPECWORK / "_state" / f"{slug}-state.json"
    if not plan_path.exists() or not state_path.exists():
        return False
    plan_mtime = plan_path.stat().st_mtime
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except Exception:
        return False
    spec_ts = state.get("spec_write_timestamp")
    if spec_ts is None:
        spec_path = state.get("spec_file", "")
        if spec_path and Path(spec_path).exists():
            spec_ts = Path(spec_path).stat().st_mtime
        else:
            return False
    return plan_mtime < spec_ts


def check_required_artifacts(slug: str) -> list[str]:
    missing: list[str] = []
    for path in [
        SPECWORK / "_state" / f"{slug}-state.json",
        SPECWORK / "_state" / f"{slug}-rules.json",
        SPECWORK / "_spec" / f"{slug}-spec.md",
    ]:
        if not path.exists():
            missing.append(str(path))
    return missing


def check_branch_match(slug: str) -> Optional[str]:
    state_path = SPECWORK / "_state" / f"{slug}-state.json"
    if not state_path.exists():
        return None
    current = _current_branch()
    if not current:
        return None
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except Exception:
        return None
    recorded = state.get("branch", "")
    if recorded and recorded != current:
        return f"BRANCH_MISMATCH recorded={recorded} current={current}"
    return None


def detect_stack() -> str:
    if any(Path(f).exists() for f in ["build.gradle", "build.gradle.kts", "pom.xml"]):
        return "java"
    if Path("package.json").exists():
        return "node"
    return "unknown"


def detect_risk_signals(spec_path: Path) -> dict[str, list[str]]:
    if not spec_path.exists():
        return {}
    text = spec_path.read_text(encoding="utf-8").lower()
    signals = {
        "db-migration": r"\b(?:migration|flyway|liquibase|alter\s+table|drop\s+(?:table|column)|create\s+table|schema\s+change|add\s+column|rename\s+column)\b",
        "auth-security": r"\b(?:authentication|authorization|oauth|jwt|security\s+config|credential|permission|role-based|access\s+control|token\s+validation|password\s+hash)\b",
        "breaking-api": r"\b(?:breaking\s+change|remove\s+endpoint|deprecate\s+endpoint|change\s+response\s+(?:format|shape)|change\s+contract|api\s+version\s+bump)\b",
        "data-destructive": r"\b(?:delete\s+data|purge|wipe|cleanup\s+data|production\s+data|truncate)\b",
        "concurrency": r"\b(?:@transactional|distributed\s+transaction|race\s+condition|two-phase\s+commit|optimistic\s+lock|pessimistic\s+lock)\b",
    }
    hits: dict[str, list[str]] = {}
    for label, pattern in signals.items():
        matches = re.findall(pattern, text)
        if matches:
            hits[label] = sorted(set(matches))[:3]
    return hits


def check_spec_consistency(spec_path: Path) -> list[str]:
    if not spec_path.exists():
        return []
    text = spec_path.read_text(encoding="utf-8")
    pairs = [
        (
            "idempotent + per-call side effect",
            r"\bidempotent(ly|cy)?\b",
            r"\b(log|audit|notify|publish|emit)\b[^.\n]{0,40}\b(on|in|per|for)\s+(each|every)\s+(call|invocation|request)\b",
            None,
        ),
        (
            "remove + still-referenced",
            r"\b(remove|delete|drop)\s+(the\s+)?(endpoint|method|class|column|field|constant)\b",
            r"\bstill\s+(referenced|used|in[- ]use)\b",
            None,
        ),
        (
            "atomic + multi-step",
            r"\batomic\b",
            r"\bmulti[- ]step\b",
            r"\b(transaction|saga|two[- ]phase|coordinator|orchestrat)\w*",
        ),
        (
            "cache + always fresh",
            r"\bcach(e|ing)\b",
            r"\b(always|fully)\s+(fresh|real[- ]time|up[- ]to[- ]date|current)\b",
            r"\b(invalidat|expir|ttl|evict|refresh\s+strategy)\w*",
        ),
    ]
    paragraphs = [p for p in re.split(r"\n\s*\n", text) if p.strip()]
    flagged: list[str] = []
    for label, pat_a, pat_b, resolver in pairs:
        in_a = {i for i, p in enumerate(paragraphs) if re.search(pat_a, p, re.IGNORECASE)}
        in_b = {i for i, p in enumerate(paragraphs) if re.search(pat_b, p, re.IGNORECASE)}
        if not in_a or not in_b:
            continue
        if in_a & in_b:
            continue
        if resolver and re.search(resolver, text, re.IGNORECASE):
            continue
        flagged.append(label)
    return flagged
