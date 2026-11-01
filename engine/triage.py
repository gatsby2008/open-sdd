"""Triage: classify a spec into a tier and write ``path.json``.

The single implementation. ``commands/triage.sh`` (run by ``/f-spec`` after the
first draft) and ``python3 -m engine.cli triage`` both call :func:`run`. Before
this module each carried its own copy and they had drifted (``focused`` was
``LOW`` in one and ``MEDIUM`` in the other; only one wrote ``skip``).

The classifier is a keyword heuristic over three spec sections:

  - high-risk keywords in ``## Behavior`` or ``## Implementation Context``;
  - trivial-change keywords in ``## Behavior``;
  - ``Expected layers`` / ``Expected files touched`` in ``## Expected Change Scope``.

It can misfire (a negated "does not publish to Kafka" still matches ``kafka``),
which is what the tier override in :mod:`engine.tier` is for.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from engine import tier as tiers
from engine.persistence import SPECWORK

HIGH_KW = (
    "async", "completablefuture", "executorservice", "@async",
    "transactional", "retry", "retrytemplate",
    "event", "sns", "sqs", "kafka", "consumer", "producer",
    "auth", "authentication", "authorization", "security",
    "migration", "flyway", "liquibase", "breaking", "concurrency",
    # Frontend high-risk keywords
    "state management", "redux", "zustand", "context api",
    "routing", "navigation", "react-router", "next.router",
    "accessibility", "a11y", "aria",
    "ssr", "hydration", "code splitting",
    "data fetching", "useswr", "react-query", "tanstack query",
    "component migration", "ui library", "design system",
    "i18n", "localization",
    "theming", "dark mode",
)
TRIVIAL_KW = ("typo", "rename", "copy change", "wording", "message change")
KNOWN_LAYERS = ("service", "controller", "repository", "config", "tests", "integration",
                "component", "page", "store", "hook", "screen", "layout", "util")


def _section(name: str, src: str) -> str:
    m = re.search(rf"(?ms)^## {re.escape(name)}\b(.*?)(?=^## |\Z)", src)
    return m.group(1).strip() if m else ""


def classify(spec: str) -> dict:
    """Automatic tier for ``spec``: ticket_type, complexity, recommended_path, skip, signals, reason."""
    behavior = _section("Behavior", spec).lower()
    impl_ctx = _section("Implementation Context", spec).lower()
    scope = _section("Expected Change Scope", spec).lower()

    matched_high = [k for k in HIGH_KW if k in behavior or k in impl_ctx]
    matched_triv = [k for k in TRIVIAL_KW if k in behavior]

    layers_match = re.search(r"expected layers[^\n]*?:\s*([^\n]+)", scope)
    layers = [L for L in KNOWN_LAYERS if layers_match and L in layers_match.group(1)]
    num_layers = len(layers)

    files_match = re.search(r"expected files touched[^\n]*?:\s*(\d+)(?:\s*-\s*(\d+))?", scope)
    if files_match:
        lo = int(files_match.group(1))
        hi = int(files_match.group(2)) if files_match.group(2) else lo
        files_estimate = (lo + hi) // 2
    else:
        files_estimate = 0

    if matched_triv and not matched_high and num_layers <= 1 and files_estimate <= 2:
        ticket_type = "trivial"
    elif matched_high or num_layers >= 4 or files_estimate >= 7:
        ticket_type = "high-risk"
    elif num_layers >= 2 or files_estimate >= 3:
        ticket_type = "standard"
    else:
        ticket_type = "focused"

    signals = []
    if matched_high:
        signals.append("high-risk keywords: " + ", ".join(matched_high[:3]))
    if matched_triv and ticket_type == "trivial":
        signals.append("trivial-change keywords: " + ", ".join(matched_triv[:3]))
    if num_layers:
        signals.append(f"{num_layers} layer(s): {', '.join(layers)}")
    if files_estimate:
        signals.append(f"~{files_estimate} files expected")

    return {
        "ticket_type": ticket_type,
        "complexity": tiers.COMPLEXITY[ticket_type],
        "recommended_path": list(tiers.PATHS[ticket_type]),
        "skip": list(tiers.SKIP[ticket_type]),
        "signals": signals,
        "reason": " · ".join(signals) if signals else "default",
    }


def run(slug: str, forced_tier: str = "", forced_reason: str = "") -> int:
    """Classify the spec of ``slug``, apply any tier override, write path.json and update state.json.

    Exit codes: 0 written · 1 no spec · 2 bad override (nothing written).
    Prints the summary on stderr and the path.json payload on stdout.
    """
    spec_path = SPECWORK / "_spec" / f"{slug}-spec.md"
    state_path = SPECWORK / "_state" / f"{slug}-state.json"
    out = SPECWORK / "_state" / f"{slug}-path.json"
    if not spec_path.exists():
        print(f"No spec found for slug: {slug}", file=sys.stderr)
        return 1

    if forced_tier and forced_tier != "auto":
        if forced_tier not in tiers.TIERS:
            print(f"✗ Unknown tier '{forced_tier}' — expected one of: {', '.join(tiers.TIERS)}, auto",
                  file=sys.stderr)
            return 2
        if not forced_reason.strip():
            print('✗ A tier override needs a reason: --tier <tier> "<reason>"', file=sys.stderr)
            return 2
    previous_override = None if forced_tier else tiers.read_override(out)

    payload = {"schema_version": 1, "id": slug,
               **classify(spec_path.read_text(encoding="utf-8"))}
    # Forced tier: explicit --tier wins; otherwise a stored override is sticky.
    if forced_tier and forced_tier != "auto":
        payload = tiers.apply_override(payload, forced_tier, forced_reason)
    elif previous_override:
        payload = tiers.apply_override(payload, previous_override["tier"], previous_override["reason"])

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    # Mirror the tier into state.json so downstream commands see it.
    if state_path.exists():
        try:
            data = json.loads(state_path.read_text(encoding="utf-8"))
            data["ticket_type"] = payload["ticket_type"]
            data["complexity"] = payload["complexity"]
            state_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        except Exception:
            pass  # non-fatal — path.json was already written

    print(tiers.summary_line(payload), file=sys.stderr)
    print(f"{out} written", file=sys.stderr)
    print(json.dumps(payload, indent=2))
    return 0
