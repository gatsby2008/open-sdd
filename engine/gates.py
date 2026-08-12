import json
import re
from pathlib import Path
from typing import Optional

# Single source of truth for the working-dir root, shared with persistence.py
# (re-exported here so callers importing it from engine.gates keep working).
from engine.persistence import SPECWORK


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


def pipeline_branch_status(branch: Optional[str] = None) -> dict:
    """Full picture of how ``.specwork/`` relates to ``branch`` (current branch
    if not given).

    ``/f-close`` (and, by the same reasoning, anything else that decides
    whether it's safe to act on "the" pipeline on disk) must not assume
    "some .specwork/ exists" means "it's mine." ``.specwork/`` is gitignored
    and survives `git checkout`, so it routinely still holds a *different*
    branch's pipeline. ``resolve_slug()``'s branch-derived fallback already
    avoids adopting an unrelated branch's *slug*, but callers that only check
    "does .specwork/_state have any state.json" (the historical pattern, e.g.
    close.sh before this fix) skip past that protection entirely.

    Returns a dict:
      current_branch        -- ``branch`` as given (or the resolved current one)
      has_any_pipeline       -- True if any ``*-state.json`` exists at all
      owns_pipeline          -- True if some state.json's ``branch`` field
                                 equals ``branch`` exactly (the normal case)
      slug                   -- the owning slug when owns_pipeline is True;
                                 otherwise the first state file's slug, purely
                                 so the caller can *name* the mismatch instead
                                 of silently acting on it — never treat this as
                                 "the current pipeline" when owns_pipeline is False
      recorded_branch         -- that slug's own recorded branch
      recorded_base_branch    -- that slug's recorded base_branch, or ""
      is_base_branch          -- True if ``branch`` equals recorded_base_branch
                                 — the "MR merged, back on the base branch to
                                 clean up" case close.sh is meant to allow, as
                                 opposed to a genuinely unrelated third branch
    """
    if branch is None:
        branch = _current_branch()
    result = {
        "current_branch": branch or "",
        "has_any_pipeline": False,
        "owns_pipeline": False,
        "slug": "",
        "recorded_branch": "",
        "recorded_base_branch": "",
        "is_base_branch": False,
    }
    state_dir = SPECWORK / "_state"
    states = sorted(state_dir.glob("*-state.json")) if state_dir.exists() else []
    if not states:
        return result
    result["has_any_pipeline"] = True

    def slug_of(p: Path) -> str:
        return p.name[: -len("-state.json")]

    if branch:
        for p in states:
            try:
                data = json.loads(p.read_text(encoding="utf-8"))
            except Exception:
                continue
            if data.get("branch") == branch:
                result["owns_pipeline"] = True
                result["slug"] = data.get("slug", data.get("id", slug_of(p)))
                result["recorded_branch"] = data.get("branch", "") or ""
                result["recorded_base_branch"] = data.get("base_branch", "") or ""
                return result

    # No match for `branch` — report the first file found purely so the
    # caller can name the mismatch; never silently act on it as "the" pipeline.
    p = states[0]
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        data = {}
    result["slug"] = data.get("slug", data.get("id", slug_of(p)))
    result["recorded_branch"] = data.get("branch", "") or ""
    result["recorded_base_branch"] = data.get("base_branch", "") or ""
    result["is_base_branch"] = bool(branch) and branch == result["recorded_base_branch"]
    return result


def _git(args: list, timeout: int = 10):
    """Run a git command. Returns ``(returncode, stdout)``; rc is ``None`` when
    git could not be run at all (not installed, timeout), which callers must
    treat as "unknown", never as "the check failed"."""
    import subprocess
    try:
        r = subprocess.run(
            ["git", *args], capture_output=True, text=True, timeout=timeout
        )
        return r.returncode, r.stdout.strip()
    except (FileNotFoundError, subprocess.SubprocessError):
        return None, ""


def branch_merge_status(branch: Optional[str], base: Optional[str], git=_git) -> str:
    """Classify a pipeline's recorded branch against its recorded base branch.

    Git-only and offline — no ``glab``, no network. Answers "has this pipeline's
    work already landed?" well enough to *warn*; it is never authority to delete.

    Returns one of:
      ``"branch-gone"``  -- no local ref for ``branch``; almost certainly merged
                            and deleted (the usual post-MR cleanup), but a rename
                            that skipped /f-resync looks identical, so callers
                            must warn rather than act
      ``"merged"``       -- ``branch`` is an ancestor of ``base`` (or
                            ``origin/<base>``): its commits are already in
      ``"open"``         -- ``branch`` exists and has not landed in a resolvable base
      ``"unknown"``      -- not a git repo, git unavailable, no base recorded, or
                            neither ``base`` nor ``origin/<base>`` resolves
    """
    if not branch:
        return "unknown"
    # One repo probe up front: outside a git repo (or with no git at all) every
    # subsequent rc is nonzero, which would masquerade as "branch-gone".
    rc, _ = git(["rev-parse", "--git-dir"])
    if rc != 0:
        return "unknown"
    rc, _ = git(["rev-parse", "--verify", "--quiet", f"refs/heads/{branch}"])
    if rc is None:
        return "unknown"
    if rc != 0:
        return "branch-gone"
    if not base:
        return "unknown"
    resolved = False
    for ref in (base, f"origin/{base}"):
        rc_ref, _ = git(["rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"])
        if rc_ref != 0:
            continue
        resolved = True
        rc_anc, _ = git(["merge-base", "--is-ancestor", branch, ref])
        if rc_anc == 0:
            return "merged"
    return "open" if resolved else "unknown"


def pipeline_inventory(branch: Optional[str] = None, git=_git) -> dict:
    """Inventory every pipeline on disk and flag the closable leftovers.

    ``.specwork/`` is gitignored, so it survives `git checkout` and outlives the
    branch it belongs to: finish a feature, merge the MR, never run /f-close, and
    its state sits there indefinitely — at which point /f-start refuses to start
    anything new ("Pipeline already active here") and points at /f-status to
    *continue* work that already shipped.

    ``pipeline_branch_status()`` answers "is this one mine?"; this answers "what
    else is lying around, and is any of it safe to close?" Purely a reporting
    call — it never deletes.

    Returns a dict:
      current_branch -- ``branch`` as given (or the resolved current one)
      pipelines      -- one entry per ``*-state.json``, each with ``slug``,
                        ``branch``, ``base_branch``, ``is_current``,
                        ``merge_status`` (see branch_merge_status; ``"active"``
                        for the current branch's own pipeline, never probed)
                        and ``closable``
      orphans        -- pipelines not owned by ``branch``
      closable       -- orphans whose work already landed (``merged`` /
                        ``branch-gone``) — the ones to name in a /f-close warning
    """
    if branch is None:
        branch = _current_branch()
    state_dir = SPECWORK / "_state"
    states = sorted(state_dir.glob("*-state.json")) if state_dir.exists() else []
    pipelines = []
    for p in states:
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            data = {}
        recorded = data.get("branch", "") or ""
        base = data.get("base_branch", "") or ""
        is_current = bool(branch) and recorded == branch
        status = "active" if is_current else branch_merge_status(recorded, base, git)
        pipelines.append({
            "slug": data.get("slug", data.get("id", p.name[: -len("-state.json")])),
            "branch": recorded,
            "base_branch": base,
            "is_current": is_current,
            "merge_status": status,
            "closable": (not is_current) and status in ("merged", "branch-gone"),
        })
    return {
        "current_branch": branch or "",
        "pipelines": pipelines,
        "orphans": [x for x in pipelines if not x["is_current"]],
        "closable": [x for x in pipelines if x["closable"]],
    }


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
    """The state file for the *current branch's* pipeline, or None if it has none.

    Deliberately does not fall back to "the first state file found" when the
    resolved slug has no matching file. .specwork/ is gitignored and survives
    `git checkout`, so it commonly still holds a different branch's leftover
    pipeline state; treating that as this branch's active pipeline would be
    wrong (mirrors resolve_slug()'s own branch-scoped matching above).
    """
    slug = resolve_slug()
    if slug:
        p = SPECWORK / "_state" / f"{slug}-state.json"
        if p.exists():
            return p
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


def ticket_from_branch(branch: str) -> tuple[str, str]:
    """Return ``(ticket, input_type)`` from a branch name.

    Strict canonical Jira key (IR-70, MYYES-1234) → ``(KEY, "jira")``; dotted
    variant (IR-70.1), not API-queryable → ``(KEY, "freetext")``; no match →
    ``("", "freetext")``.
    """
    unprefixed = re.sub(r"^(feature|hotfix|release|bugfix)/", "", branch).upper()
    strict = re.match(r"^([A-Z]+-[0-9]+)(?:-|$)", unprefixed)
    if strict:
        return strict.group(1), "jira"
    loose = re.match(r"^([A-Z]+-[0-9.]+)(?:-|$)", unprefixed)
    if loose:
        return loose.group(1), "freetext"
    return "", "freetext"


def _oq_section(slug: str) -> str:
    spec = SPECWORK / "_spec" / f"{slug}-spec.md"
    if not spec.exists():
        return ""
    text = spec.read_text(encoding="utf-8")
    m = re.search(r"(?ms)^## Open Questions\b(.*?)(?=^## |\Z)", text)
    return m.group(1) if m else ""


def count_open_questions(slug: str) -> tuple[int, int]:
    """Return ``(open, resolved)`` OQ counts from the spec (``[ ]`` vs ``[x]``)."""
    section = _oq_section(slug)
    open_n = len([l for l in section.splitlines() if re.match(r"^\s*-\s*\[\s*\]", l)])
    resolved_n = len([l for l in section.splitlines() if re.match(r"^\s*-\s*\[[xX]\]", l)])
    return open_n, resolved_n


def get_resolved_oqs(slug: str) -> dict[str, str]:
    """Return ``{question: answer}`` for resolved OQs (``- [x] q — a``)."""
    out: dict[str, str] = {}
    for l in _oq_section(slug).splitlines():
        m = re.match(r"^\s*-\s*\[[xX]\]\s*(.+)$", l)
        if not m:
            continue
        body = m.group(1).strip()
        if "—" in body:
            q, a = body.split("—", 1)
            out[q.strip()] = a.strip()
        else:
            out[body] = ""
    return out


def format_staleness_error(slug: str) -> str:
    """Human-readable staleness message, or "" when the plan is fresh/absent."""
    if not check_plan_staleness(slug):
        return ""
    return (
        f"Plan is stale: .specwork/_plan/{slug}-plan.md is older than the spec "
        f"(the spec changed after the plan was written). Re-run /f-plan to refresh it, "
        f"or delete the plan to force a rebuild."
    )


def audit_artifacts(slug: str) -> dict:
    """Existence + mtime for every artifact of a slug, keyed by artifact name."""
    artifacts = {
        "state_file": SPECWORK / "_state" / f"{slug}-state.json",
        "rules_file": SPECWORK / "_state" / f"{slug}-rules.json",
        "cache_file": SPECWORK / "_state" / f"{slug}-implementation-cache.json",
        "path_file": SPECWORK / "_state" / f"{slug}-path.json",
        "spec_file": SPECWORK / "_spec" / f"{slug}-spec.md",
        "source_file": SPECWORK / "_spec" / f"{slug}-source.md",
        "plan_file": SPECWORK / "_plan" / f"{slug}-plan.md",
        "context_file": SPECWORK / "_progress" / f"{slug}-context.md",
    }
    result = {}
    for name, p in artifacts.items():
        exists = p.exists()
        result[name] = {"path": str(p), "exists": exists, "mtime": p.stat().st_mtime if exists else None}
    return result


def detect_stack() -> str:
    if any(Path(f).exists() for f in ["build.gradle", "build.gradle.kts", "pom.xml"]):
        return "java"
    if not Path("package.json").exists():
        return "unknown"
    # Frontend frameworks: check for common config files first
    frontend_configs = [
        "vite.config.ts", "vite.config.js", "vite.config.mjs",
        "next.config.js", "next.config.ts", "next.config.mjs",
        "angular.json", "svelte.config.js", "nuxt.config.ts",
        "nuxt.config.js", "vue.config.js", "remix.config.js",
        "astro.config.mjs",
    ]
    if any(Path(f).exists() for f in frontend_configs):
        return "frontend"
    # Fallback: check package.json for frontend framework dependencies
    try:
        pkg = json.loads(Path("package.json").read_text(encoding="utf-8"))
        deps = {**pkg.get("dependencies", {}), **pkg.get("devDependencies", {})}
        frontend_kw = {"react", "vue", "@angular/core", "svelte", "preact", "solid-js", "lit"}
        if frontend_kw & set(deps.keys()):
            return "frontend"
    except Exception:
        pass
    return "node"


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
        # Frontend risk signals
        "component-api": r"\b(?:component\s+api|props?\s+(?:interface|type|shape)|breaking\s+change\s+in\s+component|rename\s+prop|remove\s+prop|change\s+(?:prop|render)\s+(?:type|signature))\b",
        "state-management": r"\b(?:state\s+management|redux|zustand|context\s+api|mobx|recoil|jotai|migration\s+(?:from|to)\s+(?:redux|zustand|context)|replace\s+(?:redux|zustand|context))\b",
        "accessibility": r"\b(?:a11y|accessibility|aria[-_]\w*|screen\s+reader|keyboard\s+navigat|focus\s+trap|role\s*=|tab\s*index|wcag|contrast\s+ratio)\b",
        "routing": r"\b(?:routing|navigation|react-router|next\.router|userouter|navigate|redirect|route\s+(?:structure|change|restructure))\b",
        "data-fetching": r"\b(?:data\s+fetching|useswr|react-query|tanstack\s+query|apollo\s+client|graphql|usequery|usemutation|ssr|server-side\s+rendering|hydration|getserversideprops|getstaticprops|getstaticpaths)\b",
        "ui-migration": r"\b(?:ui[- ]library\s+(?:upgrade|migration|bump)|migrat(?:e|ion)\s+(?:from|to)\s+(?:material|antd|chakra|tailwind|bootstrap|shadcn|styled|emotion)|design\s+system\s+update|theming\s+overhaul|dark\s+mode)\b",
    }
    hits: dict[str, list[str]] = {}
    for label, pattern in signals.items():
        matches = re.findall(pattern, text)
        if matches:
            hits[label] = sorted(set(matches))[:3]
    return hits


def extract_reference_targets(spec_path: Path) -> list[str]:
    """Return symbols (backtick tokens and /-prefixed paths) that appear on
    lines containing a destructive-change trigger word, excluding lines that
    are negated ('Do NOT remove ...') and the Safe Constraints section."""
    if not spec_path.exists():
        return []
    text = spec_path.read_text(encoding="utf-8")
    trigger = re.compile(
        r"\b(renam\w*|remov\w*|delet\w*|deprecat\w*|replac\w*|migrat\w*|drop|retire|legacy)\b",
        re.IGNORECASE,
    )
    negation = re.compile(
        r"\b(?:not|never|without|keep|keeps|keeping|kept|preserv\w*|retain\w*|"
        r"maintain\w*|unchanged|untouched|intact)\b|n't",
        re.IGNORECASE,
    )
    symbols: set[str] = set()
    in_safe_constraints = False
    for line in text.splitlines():
        heading = re.match(r"^\s*##\s+(.*)", line)
        if heading:
            in_safe_constraints = heading.group(1).strip().lower().startswith("safe constraints")
            continue
        if in_safe_constraints:
            continue
        if not trigger.search(line):
            continue
        if negation.search(line):
            continue
        symbols.update(re.findall(r"`([^`]+)`", line))
        symbols.update(re.findall(r"/[a-zA-Z][\w\-/{}]*", line))
    return sorted(s for s in symbols if len(s) >= 3 and " " not in s)


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
