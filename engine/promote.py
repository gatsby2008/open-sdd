"""Promote durable rules from a closed spec into the team's rules files, append-only.

``/f-close`` proposes candidate rules from the spec; the user approves each
one; this module performs the write. The guarantee lives here, in code, not in
prose: rules files mix hand-written business rules and design rationale, so
every pre-existing line must survive byte-for-byte and in order. ``apply``
only ever *inserts* lines and refuses to write if the result is anything else.

Targets are the shared, committed rules under ``rules/*.md`` (the neutral home,
preferred) or, as a legacy fallback, ``.claude/rules/*.md`` — which ``/f-start``
syncs into the personal ``.opensdd/service-rules.md`` — never ``.opensdd/``
itself: it is gitignored and ``/f-close`` deletes it.

Each inserted bullet carries a provenance marker so promoted rules stay
distinguishable from hand-written ones::

    - <rule> _(from spec <slug>, <YYYY-MM-DD>)_

Wired as ``python3 -m engine.cli promote-apply <slug> '<json>' [--dry-run]``
where ``<json>`` = ``[{"file": "rules/x.md", "section": "...", "rule": "..."}, ...]``.
``.claude/rules/x.md`` is also accepted while a repository is on the legacy home.
"""
from __future__ import annotations

import datetime
import difflib
import re
from pathlib import Path


def rules_home() -> Path:
    """Resolve the repo's shared-rules home: neutral ``rules/`` preferred,
    legacy ``.claude/rules/`` as fallback for not-yet-migrated repos, else
    ``rules/`` for a fresh repo. Read and write must agree per repository."""
    for p in (Path("rules"), Path(".claude") / "rules"):
        if p.exists():
            return p
    return Path("rules")


def _allowed_homes() -> list[Path]:
    """All directories promoted rules may live in (neutral + legacy)."""
    return [Path("rules"), Path(".claude") / "rules"]

_HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
_BULLET = re.compile(r"^[-*]\s")


def bullet(rule: str, slug: str, date: str) -> str:
    return f"- {rule.strip()} _(from spec {slug}, {date})_"


def _find_section(lines: list[str], section: str):
    """(start, end, level) of the heading named ``section``; end is exclusive. None if absent."""
    wanted = section.strip().lstrip("#").strip().lower()
    for i, line in enumerate(lines):
        m = _HEADING.match(line)
        if m and m.group(2).lower() == wanted:
            level = len(m.group(1))
            end = len(lines)
            for j in range(i + 1, len(lines)):
                n = _HEADING.match(lines[j])
                if n and len(n.group(1)) <= level:
                    end = j
                    break
            return i, end, level
    return None


def _insertion_point(lines: list[str], start: int, end: int) -> int:
    """After the section's last bullet (and its indented continuation), else after its last non-blank line."""
    last_bullet = None
    for i in range(start + 1, end):
        if _BULLET.match(lines[i]):
            last_bullet = i
    if last_bullet is not None:
        i = last_bullet + 1
        while i < end and lines[i].startswith((" ", "\t")) and lines[i].strip():
            i += 1
        return i
    i = end
    while i > start + 1 and not lines[i - 1].strip():
        i -= 1
    return i


def insert_rules(text: str, entries: list[dict], slug: str, date: str) -> str:
    """Return ``text`` with each entry's rule inserted at the end of its section."""
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.splitlines()
    for entry in entries:
        new_line = bullet(entry["rule"], slug, date)
        found = _find_section(lines, entry["section"])
        if found is None:
            while lines and not lines[-1].strip():
                lines.pop()
            heading = "## " + entry["section"].strip().lstrip("#").strip()
            lines.extend(([""] if lines else []) + [heading, "", new_line])
            continue
        start, end, _ = found
        at = _insertion_point(lines, start, end)
        lines.insert(at, new_line)
    return newline.join(lines) + newline


def only_insertions(old: str, new: str) -> bool:
    """True when ``new`` keeps every line of ``old`` unchanged and in order."""
    matcher = difflib.SequenceMatcher(a=old.splitlines(), b=new.splitlines(), autojunk=False)
    return all(tag in ("equal", "insert") for tag, *_ in matcher.get_opcodes())


def _valid(entries: list[dict]) -> list[dict]:
    return [e for e in entries if str(e.get("rule", "")).strip() and str(e.get("section", "")).strip()]


def check_target(path) -> None:
    """Raise ValueError unless ``path`` is a markdown file under ``rules/`` or,
    as legacy fallback, under ``.claude/rules/``."""
    p = Path(path)
    if p.suffix != ".md" or p.parent not in _allowed_homes():
        raise ValueError(
            f"refusing to write {path}: promoted rules go to rules/<topic>.md "
            f"(or the legacy .claude/rules/ home)"
        )


def plan(path, slug: str, entries: list[dict], date: str | None = None):
    """(old, new) text for ``path`` after inserting ``entries``; raises ValueError on rejection."""
    date = date or datetime.date.today().isoformat()
    p = Path(path)
    old = p.read_bytes().decode("utf-8") if p.exists() else ""
    new = insert_rules(old, entries, slug, date)
    if not only_insertions(old, new):
        raise ValueError(f"refusing to write {path}: an existing line would change")
    return old, new


def apply(path, slug: str, entries: list[dict], date: str | None = None) -> int:
    """Write the approved entries into ``path``. Returns the number inserted; raises ValueError on rejection."""
    entries = _valid(entries)
    if not entries:
        return 0
    _, new = plan(path, slug, entries, date)
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(new.encode("utf-8"))
    return len(entries)


def apply_all(slug: str, entries: list[dict], dry_run: bool = False, date: str | None = None) -> dict[str, int]:
    """Group ``entries`` by ``file`` and apply each group. All files are validated before any write.

    Returns ``{file: inserted_count}``; raises ValueError (and writes nothing) on any rejection.
    """
    groups: dict[str, list[dict]] = {}
    for e in _valid(entries):
        target = str(e.get("file") or rules_home() / "service-rules.md")
        check_target(target)
        groups.setdefault(target, []).append(e)
    for target, group in groups.items():
        plan(target, slug, group, date)
    if dry_run:
        return {t: len(g) for t, g in groups.items()}
    return {t: apply(t, slug, g, date) for t, g in groups.items()}
