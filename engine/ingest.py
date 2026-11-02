"""Plan a raw -> wiki ingest — the logic behind /doc-ingest.

The `doc-*` commands write the append-only `raw/` registries. When the registry
root is the `raw/` half of a two-layer vault (a `wiki/` sibling, per the
Karpathy model), `/doc-ingest` compiles that material into the interconnected
wiki layer that `/doc-ask` navigates.

This module only answers questions — it never writes to the wiki (the model
does, following the vault schema):

  1. is there a wiki layer next to the registry root?
  2. what is the watermark (newest `## [YYYY-MM-DD]` entry of `wiki/log.md`)?
  3. which raw docs changed after it (the auto-selection)?
  4. did the user name a source, ask for `session`, or leave it empty?

`raw/` is the source of truth and is never modified; only `wiki/` is written.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Optional

# The vault schema lives at the vault root; sdd-plugin uses CLAUDE.md, open-sdd
# projects commonly use AGENTS.md. Either is authoritative when present.
SCHEMA_NAMES = ("CLAUDE.md", "AGENTS.md")

# Templates are scaffolds, not knowledge — never compile them.
SKIP_DIRS = ("templates",)

# How many pending paths to print before summarising the rest.
LIST_LIMIT = 40


def log_watermark(wiki: Path) -> str:
    """Newest `## [YYYY-MM-DD]` entry of wiki/log.md, or "never"."""
    log = wiki / "log.md"
    if not log.is_file():
        return "never"
    stamps = re.findall(r"^## \[(\d{4}-\d{2}-\d{2})\]", log.read_text(errors="replace"), re.M)
    return max(stamps) if stamps else "never"


def raw_docs(raw: Path) -> list[Path]:
    """Every markdown file under raw/, excluding template scaffolds."""
    out = []
    for path in raw.rglob("*.md"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.relative_to(raw).parts[:-1]):
            continue
        out.append(path)
    return sorted(out)


def _day(path: Path) -> str:
    return date.fromtimestamp(path.stat().st_mtime).isoformat()


def _inside(child: Path, parent: Path) -> bool:
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False


@dataclass
class IngestPlan:
    raw: Path
    wiki: Optional[Path] = None
    schema: Optional[Path] = None
    watermark: str = "never"
    pending: list[tuple[str, str]] = field(default_factory=list)
    mode: str = "auto"                    # auto | path | session
    selected: list[str] = field(default_factory=list)
    error: str = ""

    @property
    def has_wiki(self) -> bool:
        return self.wiki is not None


def plan(raw: Path, target: Optional[str] = None) -> IngestPlan:
    """Resolve the vault layout, the watermark, the pending docs and the
    requested source. `raw` is the registry root (usually $OPEN_SDD_DOC_HOME)."""
    raw = Path(raw).expanduser().resolve()
    p = IngestPlan(raw=raw)

    wiki = raw.parent / "wiki"
    if wiki.is_dir():
        p.wiki = wiki
        p.watermark = log_watermark(wiki)

    vault = raw.parent
    p.schema = next((vault / name for name in SCHEMA_NAMES if (vault / name).is_file()), None)

    docs = raw_docs(raw)
    pending = [(d, _day(d)) for d in docs]
    if p.watermark != "never":
        pending = [(d, day) for d, day in pending if day > p.watermark]
    p.pending = [(d.relative_to(raw).as_posix(), day)
                 for d, day in sorted(pending, key=lambda pair: pair[1], reverse=True)]

    wanted = (target or "").strip()
    if not wanted:
        p.mode = "auto"
        p.selected = [rel for rel, _ in p.pending]
        return p

    if wanted.lower() == "session":
        p.mode = "session"
        return p

    candidate = Path(wanted).expanduser()
    if not candidate.is_absolute():
        candidate = raw / candidate
    candidate = candidate.resolve()

    if not candidate.exists():
        p.error = (f"Source not found: {wanted}\n"
                   f"Pass a path under {raw} (e.g. service-catalog/<service>.md), "
                   "'session', or nothing to compile what is un-ingested.")
    elif not _inside(candidate, raw):
        p.error = (f"{wanted} is outside {raw}.\n"
                   "raw/ is the append-only source of truth; /doc-ingest only "
                   "compiles files that live under it.")
    elif candidate.suffix != ".md":
        p.error = f"{wanted} is not a markdown file."
    else:
        p.mode = "path"
        p.selected = [candidate.relative_to(raw).as_posix()]
    return p


def render(p: IngestPlan) -> str:
    """The context block /doc-ingest prints before its instructions."""
    vault = p.raw.parent
    out = [f"Vault: {vault}",
           f"Raw: {p.raw}",
           f"Wiki: {p.wiki or '(none — no wiki/ sibling of raw/)'}",
           f"Schema: {p.schema or '(none — follow the conventions already in wiki/)'}",
           f"Last ingest: {p.watermark}"]

    if p.watermark == "never":
        out.append(f"Un-ingested: {len(p.pending)} raw doc(s) — the wiki has no log entry yet")
    else:
        out.append(f"Un-ingested: {len(p.pending)} raw doc(s) modified after {p.watermark}")

    shown = p.pending[:LIST_LIMIT]
    for rel, day in shown:
        out.append(f"  {rel}  {day}")
    if len(p.pending) > len(shown):
        out.append(f"  … and {len(p.pending) - len(shown)} more")

    if p.mode == "session":
        out.append("Selected: session — distill this conversation into the wiki")
    elif p.mode == "path":
        out.append(f"Selected: {p.selected[0]}")
    elif p.selected:
        out.append(f"Selected (auto): {len(p.selected)} un-ingested source(s)")
    else:
        out.append("Selected (auto): nothing — the wiki already covers every raw doc")
    return "\n".join(out)
