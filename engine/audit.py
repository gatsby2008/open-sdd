"""High-risk auditor receipt for the SDD pipeline.

Reviews cost tokens, so ``/f-commit`` asks for ``/f-code-review --auditor``
**only** when triage classified the pipeline as ``high-risk``, and only once per
distinct diff. After a review, the verdict is stamped together with a
fingerprint of the diff it covered (the "receipt"); re-running ``/f-commit`` on
the same content finds a matching receipt and skips the review. The verdict is
advisory — nothing here blocks a commit.

The fingerprint is the SHA-256 of ``git diff --cached <merge-base>``: the
branch's committed work plus what is staged. It is the same before and after
the commit of that staged content, so a receipt recorded right after
``/f-commit`` still matches.

Split of responsibility:
  - ``commands/commit.sh`` asks ``audit-required`` (cheap); the agent records
    the verdict with ``audit-record`` after the review.
  - this module never runs a reviewer itself.

Wired as ``python3 -m engine.cli audit-required <slug>`` (rc 1 = run the
auditor, 0 = skip) and ``audit-record <slug> <verdict>``.
"""
from __future__ import annotations

import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from engine.persistence import SPECWORK

VERDICTS = ("PASS", "PASS WITH WARNINGS", "FAIL")


def receipt_file(slug: str) -> Path:
    return SPECWORK / "_review" / f"{slug}-audit.json"


def _read_json(path: Path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return None


def _git(args: list[str]) -> bytes:
    return subprocess.run(["git"] + args, capture_output=True, check=True).stdout


def is_high_risk(slug: str) -> bool:
    data = _read_json(SPECWORK / "_state" / f"{slug}-path.json")
    return isinstance(data, dict) and data.get("ticket_type") == "high-risk"


def diff_ref(slug: str) -> str:
    """Merge-base with the pipeline's base branch, else ``HEAD``."""
    state = _read_json(SPECWORK / "_state" / f"{slug}-state.json") or {}
    base = state.get("base_branch", "")
    if base:
        try:
            return _git(["merge-base", base, "HEAD"]).decode().strip() or "HEAD"
        except Exception:
            pass
    return "HEAD"


def diff_fingerprint(slug: str) -> str:
    """SHA-256 of the branch diff including staged changes: ``git diff --cached <merge-base>``."""
    return hashlib.sha256(_git(["diff", "--cached", diff_ref(slug)])).hexdigest()


def audit_required(slug: str) -> bool:
    """True only for a high-risk pipeline whose current diff has no receipt. Fails open."""
    try:
        if not is_high_risk(slug):
            return False
        receipt = _read_json(receipt_file(slug)) or {}
        return receipt.get("fingerprint") != diff_fingerprint(slug)
    except Exception:
        return False


def record(slug: str, verdict: str) -> str:
    """Stamp the verdict for the current diff. Returns the fingerprint; raises ValueError on a bad verdict."""
    verdict = verdict.strip().upper()
    if verdict not in VERDICTS:
        raise ValueError(f"unknown verdict {verdict!r}; expected one of {', '.join(VERDICTS)}")
    fingerprint = diff_fingerprint(slug)
    target = receipt_file(slug)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({
        "fingerprint": fingerprint,
        "verdict": verdict,
        "recorded_at": datetime.now(timezone.utc).isoformat(),
    }) + "\n", encoding="utf-8")
    return fingerprint
