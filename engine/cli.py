#!/usr/bin/env python3
"""
Entry point for all engine commands.

Usage:
    python3 -m engine.cli <command> [args...]

Will become the backend for commands/*.sh wrappers.
"""
import json
import sys
import time
from dataclasses import asdict
from pathlib import Path
from typing import Optional

from engine.state import PipelineState, load_pipeline_state, save_pipeline_state
from engine.gates import (
    resolve_slug, check_open_questions, check_required_artifacts, check_plan_staleness,
    require_specwork, SPECWORK,
)
from engine.router import next_step, FLOW_MAP
from engine.persistence import load_plan, save_plan, load_cache, save_cache


COMMANDS = [
    "start", "plan", "implement", "commit", "mr", "close",
    "test-design", "test-impl", "code-review", "handoff",
    "precheck", "check", "triage", "status", "pause", "resume", "help",
    "implement-check", "implement-done", "implement-plan",
    "resolve-slug", "detect-stack",
    "current-step", "expected-step", "advance-step", "set-step",
    "bump-spec-ts",
]


def cmd_precheck(args: list[str]) -> int:
    fresh = "--fresh" in args
    args = [a for a in args if not a.startswith("--")]
    reason = require_specwork()

    if fresh:
        # f-start gate: refuse to re-init over an already-initialized pipeline.
        if reason is None:
            print("ALREADY_INITIALIZED", file=sys.stderr)
            print("Pipeline already initialized. Use /f-spec to draft or refine the spec, "
                  "or /f-close to start over.", file=sys.stderr)
            return 1
        print("SPECWORK_FRESH")
        return 0

    if reason:
        print("NO_SPECWORK", file=sys.stderr)
        print(reason, file=sys.stderr)
        return 1
    if args:
        slug = args[0]
        if not (SPECWORK / "_state" / f"{slug}-state.json").exists():
            print(f"NO_STATE: {slug}", file=sys.stderr)
            print(f"No state file for '{slug}'. Run /f-start first.", file=sys.stderr)
            return 1
    print("SPECWORK_OK")
    return 0


def cmd_triage(args: list[str]) -> int:
    if not args:
        print("Usage: cli.py triage <slug>")
        return 1
    slug = args[0]
    return triage(slug)


def triage(slug: str) -> int:
    from engine.gates import detect_risk_signals
    from engine.persistence import load_spec

    spec = load_spec(slug)
    if not spec:
        print(f"No spec found for slug: {slug}", file=sys.stderr)
        return 1

    import re
    from pathlib import Path

    spec_text = spec.lower()
    impl_ctx_match = re.search(r"(?ms)^## Implementation Context\b(.*?)(?=^## |\Z)", spec)
    impl_ctx = impl_ctx_match.group(1).lower() if impl_ctx_match else ""

    scope_match = re.search(r"(?ms)^## Expected Change Scope\b(.*?)(?=^## |\Z)", spec)
    scope = scope_match.group(1).lower() if scope_match else ""

    high_kw = (
        "async", "completablefuture", "executorservice", "@async",
        "transactional", "retry", "retrytemplate",
        "event", "sns", "sqs", "kafka", "consumer", "producer",
        "auth", "authentication", "authorization", "security",
        "migration", "flyway", "liquibase", "breaking", "concurrency",
    )
    trivial_kw = ("typo", "rename", "copy change", "wording", "message change")

    matched_high = [k for k in high_kw if k in spec_text or k in impl_ctx]
    matched_triv = [k for k in trivial_kw if k in spec_text]

    known_layers = ("service", "controller", "repository", "config", "tests", "integration")
    layers_match = re.search(r"expected layers[^\n]*?:\s*([^\n]+)", scope)
    layers = [L for L in known_layers if layers_match and L in layers_match.group(1)]
    num_layers = len(layers)

    files_match = re.search(r"expected files touched[^\n]*?:\s*(\d+)(?:\s*-\s*(\d+))?", scope)
    if files_match:
        lo = int(files_match.group(1))
        hi = int(files_match.group(2)) if files_match.group(2) else lo
        files_estimate = (lo + hi) // 2
    else:
        files_estimate = 0

    if matched_triv and not matched_high and num_layers <= 1 and files_estimate <= 2:
        ticket_type, complexity = "trivial", "LOW"
    elif matched_high or num_layers >= 4 or files_estimate >= 7:
        ticket_type, complexity = "high-risk", "HIGH"
    elif num_layers >= 2 or files_estimate >= 3:
        ticket_type, complexity = "standard", "MEDIUM"
    else:
        ticket_type, complexity = "focused", "MEDIUM"

    flow = FLOW_MAP.get(ticket_type, FLOW_MAP["feature"])
    signals = []
    if matched_high:
        signals.append("high-risk keywords: " + ", ".join(matched_high[:3]))
    if matched_triv and ticket_type == "trivial":
        signals.append("trivial-change keywords: " + ", ".join(matched_triv[:3]))
    if num_layers:
        signals.append(f"{num_layers} layer(s): {', '.join(layers)}")
    if files_estimate:
        signals.append(f"~{files_estimate} files expected")

    payload = {
        "schema_version": 1,
        "id": slug,
        "ticket_type": ticket_type,
        "complexity": complexity,
        "recommended_path": flow,
        "signals": signals,
        "reason": " · ".join(signals) if signals else "default",
    }

    out_path = Path(f".specwork/_state/{slug}-path.json")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Written {out_path}")
    print(json.dumps(payload, indent=2))
    return 0


def cmd_status(args: list[str]) -> int:
    slug = resolve_slug()
    if not slug:
        print("Could not resolve slug from current branch.", file=sys.stderr)
        return 1
    state = load_pipeline_state(slug)
    if not state:
        print(f"No pipeline state found for slug: {slug}", file=sys.stderr)
        return 1
    print(f"Slug:    {state.slug}")
    print(f"Branch:  {state.branch}")
    print(f"Ticket:  {state.ticket or '(none)'}")
    print(f"Type:    {state.ticket_type}")
    print(f"Step:    {state.current_step} (index {state.step_index})")
    print(f"Retries: {state.retries}/{state.max_retries}")
    next_s = state.next_step()
    print(f"Next:    {next_s}")
    return 0


def cmd_check(args: list[str]) -> int:
    slug = args[0] if args else resolve_slug()
    if not slug:
        print("Could not resolve slug.", file=sys.stderr)
        return 1

    missing = check_required_artifacts(slug)
    if missing:
        for m in missing:
            print(f"MISSING: {m}", file=sys.stderr)
        return 1

    oq_blockers = check_open_questions(slug)
    if oq_blockers:
        for path_str, items in oq_blockers:
            p = Path(path_str)
            text = p.read_text(encoding="utf-8")
            lines = text.splitlines()
            oq_line = next((i + 1 for i, ln in enumerate(lines) if ln.startswith("## Open Questions")), None)
            abs_path = str(p.resolve())
            suffix = f":{oq_line}" if oq_line else ""
            print(f"UNRESOLVED OQs in `{abs_path}{suffix}`:", file=sys.stderr)
            for line in items:
                print(f"  {line}", file=sys.stderr)
        return 1

    print("All gates passed.")
    return 0


def cmd_implement_check(args: list[str]) -> int:
    slug = args[0] if args else resolve_slug()
    if not slug:
        print("COULD_NOT_RESOLVE_SLUG", file=sys.stderr)
        return 1

    missing = check_required_artifacts(slug)
    if missing:
        for m in missing:
            print(f"MISSING: {m}", file=sys.stderr)
        return 1

    oq_blockers = check_open_questions(slug)
    if oq_blockers:
        print("UNRESOLVED_OQS", file=sys.stderr)
        for path_str, items in oq_blockers:
            p = Path(path_str)
            text = p.read_text(encoding="utf-8")
            lines = text.splitlines()
            oq_line = next((i + 1 for i, ln in enumerate(lines) if ln.startswith("## Open Questions")), None)
            abs_path = str(p.resolve())
            suffix = f":{oq_line}" if oq_line else ""
            print(f"--- `{abs_path}{suffix}`", file=sys.stderr)
            for l in items:
                print(f"  {l}", file=sys.stderr)
        return 1

    # Plan is optional. /f-implement falls back to inline discovery from the
    # spec when plan.json is absent (small/obvious changes don't require a
    # plan). Staleness only applies when a plan exists.
    plan = load_plan(slug)
    if plan and check_plan_staleness(slug):
        print("PLAN_STALE")
        return 1

    print("GATES_PASSED")
    print(json.dumps({"slug": slug, "target_count": len(plan) if plan else 0}))
    return 0


def cmd_implement_done(args: list[str]) -> int:
    if len(args) < 2:
        print("Usage: cli.py implement-done <slug> <target_num>", file=sys.stderr)
        return 1
    slug = args[0]
    try:
        target_num = int(args[1])
    except ValueError:
        print(f"Invalid target number: {args[1]}", file=sys.stderr)
        return 1
    idx = target_num - 1

    plan = load_plan(slug)
    if not plan:
        print("NO_PLAN", file=sys.stderr)
        return 1
    if idx < 0 or idx >= len(plan):
        print(f"Invalid target #{target_num} (valid: 1-{len(plan)})", file=sys.stderr)
        return 1

    plan[idx]["status"] = "done"
    save_plan(slug, plan)

    cache = load_cache(slug) or {}
    notes = cache.get("notes", [])
    note = f"implemented: {plan[idx].get('path', '?')}"
    if note not in notes:
        notes.append(note)
    cache["notes"] = notes
    save_cache(slug, cache)

    remaining = len(plan) - target_num
    result = {"target": target_num, "remaining": remaining}
    if remaining <= 0:
        result["status"] = "ALL_DONE"
    else:
        result["status"] = "MORE_REMAINING"
    print(json.dumps(result))
    return 0


def cmd_implement_plan(args: list[str]) -> int:
    slug = args[0] if args else resolve_slug()
    if not slug:
        print("COULD_NOT_RESOLVE_SLUG", file=sys.stderr)
        return 1
    plan = load_plan(slug)
    if not plan:
        # No plan → no-plan workflow. Return a well-formed empty payload so
        # downstream scripts can extract fields without KeyError.
        print(json.dumps({
            "targets": [], "resume_index": 0, "resume_target": 0, "total": 0,
        }))
        return 0
    resume_idx = 0
    for i, t in enumerate(plan):
        if t.get("status") not in ("done", "skip"):
            resume_idx = i
            break
    else:
        resume_idx = len(plan)
    print(json.dumps({
        "targets": plan,
        "resume_index": resume_idx,
        "resume_target": resume_idx + 1,
        "total": len(plan),
    }))
    return 0


def cmd_detect_stack(args: list[str]) -> int:
    from engine.gates import detect_stack
    print(detect_stack())
    return 0


def cmd_resolve_slug(args: list[str]) -> int:
    slug = resolve_slug()
    if slug:
        print(slug)
        return 0
    print("COULD_NOT_RESOLVE_SLUG", file=sys.stderr)
    return 1


def cmd_current_step(args: list[str]) -> int:
    slug = args[0] if args else resolve_slug()
    if not slug:
        print("COULD_NOT_RESOLVE_SLUG", file=sys.stderr)
        return 1
    state = load_pipeline_state(slug)
    if not state:
        print("NO_STATE", file=sys.stderr)
        return 1
    print(state.current_step)
    return 0


def cmd_expected_step(args: list[str]) -> int:
    if len(args) < 1:
        print("Usage: cli.py expected-step <step> [slug]", file=sys.stderr)
        return 1
    expected = args[0]
    slug = args[1] if len(args) > 1 else resolve_slug()
    if not slug:
        print("COULD_NOT_RESOLVE_SLUG", file=sys.stderr)
        return 1
    state = load_pipeline_state(slug)
    if not state:
        print(f"NO_STATE for slug={slug}", file=sys.stderr)
        return 1
    from engine.router import flow_for, is_optional
    flow = flow_for(state.ticket_type)
    suggested = state.next_step()
    if expected not in flow:
        print(f"STEP_NOT_IN_FLOW step={expected} ticket_type={state.ticket_type} flow={','.join(flow)}", file=sys.stderr)
        print(f"✗ '{expected}' is not a step in the {state.ticket_type} flow.", file=sys.stderr)
        print(f"  Run next: {suggested}", file=sys.stderr)
        return 1
    if state.current_step == expected:
        print("ok")
        return 0
    # Forward skip: allowed only when every step from the current position up to
    # (but not including) the requested step is optional. This lets the developer
    # jump ahead past optional steps (e.g. test-design → commit) without an
    # override, while still blocking backward moves and skips over required steps.
    if state.current_step in flow:
        cur_idx = flow.index(state.current_step)
        exp_idx = flow.index(expected)
        if exp_idx > cur_idx and all(is_optional(flow[k]) for k in range(cur_idx, exp_idx)):
            print("ok")
            return 0
    print(f"WRONG_STEP expected={expected} actual={state.current_step} ticket_type={state.ticket_type}", file=sys.stderr)
    print(f"✗ Out of sequence: '{expected}' is not reachable from the current step.", file=sys.stderr)
    print(f"  Pipeline is at: {state.current_step} ({state.ticket_type})", file=sys.stderr)
    print(f"  Run next: {suggested}", file=sys.stderr)
    return 1


def cmd_advance_step(args: list[str]) -> int:
    # Usage: advance-step [slug] [completed_step]
    # When completed_step is given, the pipeline advances to the step *after* it,
    # regardless of where current_step sat. This keeps state correct when a
    # command was reached by skipping optional steps (e.g. commit run while the
    # pipeline still pointed at test-design must land on mr, not test-impl).
    slug = args[0] if args else resolve_slug()
    if not slug:
        print("COULD_NOT_RESOLVE_SLUG", file=sys.stderr)
        return 1
    completed = args[1] if len(args) > 1 else None
    state = load_pipeline_state(slug)
    if not state:
        print(f"NO_STATE for slug={slug}", file=sys.stderr)
        return 1
    if state.current_step == "done":
        print("done")
        return 0
    from engine.router import flow_for
    flow = flow_for(state.ticket_type)
    anchor = completed if (completed and completed in flow) else state.current_step
    if anchor not in flow:
        state.current_step = flow[0]
        state.step_index = 0
    else:
        next_idx = flow.index(anchor) + 1
        if next_idx >= len(flow):
            state.current_step = "done"
            state.step_index = len(flow)
        else:
            state.current_step = flow[next_idx]
            state.step_index = next_idx
    state.retries = 0
    save_pipeline_state(state)
    print(state.current_step)
    return 0


def cmd_set_step(args: list[str]) -> int:
    if len(args) < 1:
        print("Usage: cli.py set-step <step> [slug]", file=sys.stderr)
        return 1
    step = args[0]
    slug = args[1] if len(args) > 1 else resolve_slug()
    if not slug:
        print("COULD_NOT_RESOLVE_SLUG", file=sys.stderr)
        return 1
    state = load_pipeline_state(slug)
    if not state:
        print(f"NO_STATE for slug={slug}", file=sys.stderr)
        return 1
    from engine.router import flow_for
    flow = flow_for(state.ticket_type)
    if step != "done" and step not in flow:
        print(f"STEP_NOT_IN_FLOW step={step} ticket_type={state.ticket_type} flow={','.join(flow)}", file=sys.stderr)
        return 1
    state.current_step = step
    state.step_index = flow.index(step) if step in flow else len(flow)
    state.retries = 0
    save_pipeline_state(state)
    print(state.current_step)
    return 0


def cmd_bump_spec_ts(args: list[str]) -> int:
    slug = args[0] if args else resolve_slug()
    if not slug:
        print("COULD_NOT_RESOLVE_SLUG", file=sys.stderr)
        return 1
    state = load_pipeline_state(slug)
    if not state:
        print(f"NO_STATE for slug={slug}", file=sys.stderr)
        return 1
    state.spec_write_timestamp = int(time.time())
    save_pipeline_state(state)
    print(state.spec_write_timestamp)
    return 0


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(f"Usage: python3 -m engine.cli <{'|'.join(COMMANDS)}> [args...]")
        print(f"Commands: {', '.join(COMMANDS)}")
        return 1

    command = sys.argv[1]
    args = sys.argv[2:]

    dispatch = {
        "precheck": cmd_precheck,
        "triage": cmd_triage,
        "status": cmd_status,
        "check": cmd_check,
        "implement-check": cmd_implement_check,
        "implement-done": cmd_implement_done,
        "implement-plan": cmd_implement_plan,
        "resolve-slug": cmd_resolve_slug,
        "detect-stack": cmd_detect_stack,
        "current-step": cmd_current_step,
        "expected-step": cmd_expected_step,
        "advance-step": cmd_advance_step,
        "set-step": cmd_set_step,
        "bump-spec-ts": cmd_bump_spec_ts,
    }

    handler = dispatch.get(command)
    if handler:
        return handler(args)

    print(f"Command '{command}' not yet implemented via Python backend.", file=sys.stderr)
    print(f"Currently implemented: {', '.join(dispatch.keys())}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
