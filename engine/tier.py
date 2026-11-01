"""Triage tier tables, the explicit tier override, and the plan-required rule.

``commands/triage.sh`` classifies the spec automatically. The classifier reads
keywords, so it can misfire — e.g. "does **not** publish to Kafka" still
matches ``kafka`` and lands the ticket in ``high-risk``. ``/f-spec --tier
<tier> "<reason>"`` forces a tier, in either direction:

  - the override is stored in ``path.json`` as an ``override`` block
    (``tier``, ``reason``, ``auto_tier``, ``auto_reason``) and rewrites
    ``ticket_type``, ``complexity``, ``recommended_path`` and ``skip``;
  - a reason is mandatory, so the decision stays auditable;
  - it is sticky: a later triage run re-applies it; ``--tier auto`` drops it.

``plan_required`` is the rule behind ``/f-implement``'s plan-required gate:
a high-risk pipeline must have a plan before implementing. A forced tier wins
over the automatic one.
"""
from __future__ import annotations

import json
from pathlib import Path

from engine.persistence import SPECWORK

COMPLEXITY = {"trivial": "LOW", "focused": "LOW", "standard": "MEDIUM", "high-risk": "HIGH"}

# Recommended path and skipped steps per tier — the table triage.sh writes.
PATHS = {
    "trivial":   ["f-commit", "f-mr"],
    "focused":   ["f-implement", "f-commit", "f-mr"],
    "standard":  ["f-plan", "f-implement", "f-commit", "f-mr"],
    "high-risk": ["f-plan", "f-implement", "f-test-design", "f-test-impl", "f-commit", "f-mr"],
}
_ALL_STEPS = ["f-plan", "f-implement", "f-test-design", "f-test-impl"]
SKIP = {tier: [s for s in _ALL_STEPS if s not in path] for tier, path in PATHS.items()}

TIERS = tuple(PATHS)


def apply_override(payload: dict, tier: str, reason: str) -> dict:
    """Return ``payload`` (a triage result) with ``tier`` forced. Raises ValueError on bad input."""
    if tier not in PATHS:
        raise ValueError(f"unknown tier {tier!r}; expected one of {', '.join(TIERS)}")
    reason = (reason or "").strip()
    if not reason:
        raise ValueError("a tier override needs a reason")
    auto = payload.get("override", {}) or {}
    return {
        **payload,
        "ticket_type": tier,
        "complexity": COMPLEXITY[tier],
        "recommended_path": list(PATHS[tier]),
        "skip": list(SKIP[tier]),
        "reason": f"override: {reason}",
        "override": {
            "tier": tier,
            "reason": reason,
            "auto_tier": auto.get("auto_tier", payload.get("ticket_type")),
            "auto_reason": auto.get("auto_reason", payload.get("reason")),
        },
    }


def read_override(path_json) -> dict | None:
    """The ``override`` block of an existing path.json, when valid; else None."""
    try:
        data = json.loads(Path(path_json).read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return None
    override = data.get("override") if isinstance(data, dict) else None
    if isinstance(override, dict) and override.get("tier") in PATHS and str(override.get("reason", "")).strip():
        return override
    return None


def summary_line(payload: dict) -> str:
    line = f"Triage: {payload['ticket_type']} ({payload['complexity']}) — {payload['reason']}"
    override = payload.get("override")
    if override:
        line += (f"\nOverride: forced {override['tier']} "
                 f"(auto: {override['auto_tier']} — {override['auto_reason']})")
    return line


def plan_required(slug: str) -> bool:
    """True when the pipeline's tier — forced or automatic — is high-risk. No path.json → False."""
    try:
        data = json.loads((SPECWORK / "_state" / f"{slug}-path.json").read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return False
    if not isinstance(data, dict):
        return False
    override = data.get("override")
    if isinstance(override, dict) and override.get("tier") in PATHS:
        return override["tier"] == "high-risk"
    return data.get("ticket_type") == "high-risk"
