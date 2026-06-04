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
from engine.persistence import load_plan, save_plan, load_cache, save_cache


COMMANDS = [
    "start", "plan", "implement", "commit", "mr", "close",
    "test-design", "test-impl", "code-review", "handoff",
    "precheck", "check", "triage", "status", "pause", "resume", "help",
    "implement-check", "implement-done", "implement-plan",
    "resolve-slug", "detect-stack", "risk-signals",
    "bump-spec-ts", "coverage-check", "extract-reference-targets",
    "count-oqs", "audit",
    "derive-branch", "worktree-clean", "worktree-dirty",
    "commit-subject", "mr-title", "branch-classify", "requires-clean-tree",
    "stash-list", "stash-stale", "rename-slug",
]


# Advisory flows per ticket type — used by triage to print the recommended
# path. NOT enforced (no step machine); each command is independently
# artifact-gated. Keep this table in sync with /f-help and docs/learning.
FLOW_MAP: dict[str, list[str]] = {
    "feature":      ["spec", "plan", "implement", "commit", "mr", "close"],
    "bugfix":       ["spec", "implement", "commit", "mr", "close"],
    "refactor":     ["plan", "implement", "commit", "mr", "close"],
    "chore":        ["implement", "commit", "mr", "close"],
    "high-risk":    ["plan", "implement", "test-design", "test-impl", "commit", "mr", "close"],
    "standard":     ["plan", "implement", "commit", "mr", "close"],
    "focused":      ["implement", "commit", "mr", "close"],
    "trivial":      ["commit", "mr", "close"],
    "security_fix": ["spec", "implement", "commit", "mr", "close"],
}


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
        # Frontend high-risk keywords
        "state management", "redux", "zustand", "context api",
        "routing", "navigation", "react-router", "next.router",
        "accessibility", "a11y", "aria",
        "ssr", "hydration", "code splitting",
        "data fetching", "useSWR", "react-query", "tanstack query",
        "component migration", "ui library", "design system",
        "i18n", "localization",
        "theming", "dark mode",
    )
    trivial_kw = ("typo", "rename", "copy change", "wording", "message change")

    matched_high = [k for k in high_kw if k in spec_text or k in impl_ctx]
    matched_triv = [k for k in trivial_kw if k in spec_text]

    known_layers = ("service", "controller", "repository", "config", "tests", "integration",
                    "component", "page", "store", "hook", "screen", "layout", "util")
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
    print(f"Complexity: {state.complexity}")
    # Next-step recommendation lives in commands/status.sh (artifact-driven).
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


def cmd_risk_signals(args: list[str]) -> int:
    # Print the concrete, deterministic risk signals in the spec (one label per
    # line): db-migration, auth-security, breaking-api, data-destructive,
    # concurrency. These are keyword matches, not the fuzzy triage tier — /f-auto
    # uses them to decide whether to pause and ask about the test steps. No
    # signals → no output, rc 0.
    from engine.gates import detect_risk_signals
    slug = args[0] if args else resolve_slug()
    if not slug:
        print("COULD_NOT_RESOLVE_SLUG", file=sys.stderr)
        return 1
    hits = detect_risk_signals(SPECWORK / "_spec" / f"{slug}-spec.md")
    for label in hits:
        print(label)
    return 0


def cmd_extract_reference_targets(args: list[str]) -> int:
    # Print one symbol per line from the spec: backtick tokens and /-prefixed
    # paths found on destructive-change trigger lines, excluding negated lines
    # and the Safe Constraints section. Used by /f-plan to scope reference-update
    # searches. No symbols → no output, rc 0.
    from engine.gates import extract_reference_targets
    slug = args[0] if args else resolve_slug()
    if not slug:
        print("COULD_NOT_RESOLVE_SLUG", file=sys.stderr)
        return 1
    for symbol in extract_reference_targets(SPECWORK / "_spec" / f"{slug}-spec.md"):
        print(symbol)
    return 0


def cmd_derive_branch(args: list[str]) -> int:
    import re
    from engine.gates import ticket_from_branch, _current_branch
    branch = args[0] if args else _current_branch()
    if not branch:
        print("COULD_NOT_RESOLVE_BRANCH", file=sys.stderr)
        return 1
    unprefixed = re.sub(r"^(feature|hotfix|release|bugfix)/", "", branch)
    slug = re.sub(r"[^a-z0-9]+", "-", unprefixed.lower()).strip("-")
    tkt, itype = ticket_from_branch(branch)
    print(json.dumps({"branch": branch, "slug": slug, "ticket": tkt, "input_type": itype}, indent=2))
    return 0


def cmd_worktree_clean(args: list[str]) -> int:
    from engine.worktree import is_clean
    return 0 if is_clean("--exclude-agent-files" in args) else 1


def cmd_worktree_dirty(args: list[str]) -> int:
    from engine.worktree import dirty_files
    for f in dirty_files("--exclude-agent-files" in args):
        print(f)
    return 0


def cmd_commit_subject(args: list[str]) -> int:
    from engine.titles import commit_subject
    print(commit_subject(args[0], args[1], " ".join(args[2:])))
    return 0


def cmd_mr_title(args: list[str]) -> int:
    from engine.titles import mr_title
    print(mr_title(args[0], args[1], " ".join(args[2:])))
    return 0


def cmd_branch_classify(args: list[str]) -> int:
    from engine.branches import classify_branch
    print(classify_branch(args[0]))
    return 0


def cmd_requires_clean_tree(args: list[str]) -> int:
    from engine.branches import requires_clean_tree
    return 0 if requires_clean_tree(args[0]) else 1


def cmd_stash_list(args: list[str]) -> int:
    from engine.stash import list_kept_and_stale
    kept, _ = list_kept_and_stale()
    for ref, branch in kept:
        print(f"{ref}\t{branch}")
    return 0


def cmd_stash_stale(args: list[str]) -> int:
    from engine.stash import list_kept_and_stale
    _, stale = list_kept_and_stale()
    for ref, _branch in stale:
        print(ref)
    return 0


def cmd_rename_slug(args: list[str]) -> int:
    from engine.persistence import rename_slug_in_state
    if len(args) < 6:
        print("Usage: rename-slug <state_path> <new_slug> <old_slug> <branch> <ticket> <input_type>", file=sys.stderr)
        return 2
    rename_slug_in_state(args[0], args[1], args[2], args[3], args[4], args[5])
    return 0


def cmd_count_oqs(args: list[str]) -> int:
    from engine.gates import count_open_questions
    slug = args[0] if args else resolve_slug()
    if not slug:
        print("COULD_NOT_RESOLVE_SLUG", file=sys.stderr)
        return 1
    open_n, resolved_n = count_open_questions(slug)
    print(f"{open_n} {resolved_n}")
    return 0


def cmd_audit(args: list[str]) -> int:
    from engine.gates import audit_artifacts
    slug = args[0] if args else resolve_slug()
    if not slug:
        print("COULD_NOT_RESOLVE_SLUG", file=sys.stderr)
        return 1
    print(json.dumps(audit_artifacts(slug), indent=2))
    return 0


def cmd_coverage_check(args: list[str]) -> int:
    # Strict test-coverage gate: a changed production class with no matching test
    # blocks the commit. Stack-aware (java/frontend); conservative on what counts
    # as testable (DTOs/config/entities excluded). Escape hatch is a per-class
    # waiver-with-reason file. Unknown/node stacks pass cleanly. rc 1 = blocked.
    from engine import coverage
    from engine.gates import detect_stack
    slug = args[0] if args else (resolve_slug() or None)
    stack = detect_stack()
    if stack not in ("java", "frontend"):
        return 0
    offenders = coverage.classes_missing_tests(
        coverage.changed_files(), coverage.all_repo_files(), stack,
        waived=coverage.load_waivers(slug),
    )
    if not offenders:
        return 0
    waiver_file = coverage.waiver_paths(slug)[0]
    print(f"✗ Blocked: {len(offenders)} changed class(es) lack a matching test:", file=sys.stderr)
    for o in offenders:
        print(f"    - {o}", file=sys.stderr)
    print(
        f"\nAdd a test for each, or waive a class with no testable surface in\n  {waiver_file}",
        file=sys.stderr,
    )
    print(
        '  e.g. { "' + offenders[0] + '": "pure config, no testable logic" }',
        file=sys.stderr,
    )
    return 1


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
        "risk-signals": cmd_risk_signals,
        "extract-reference-targets": cmd_extract_reference_targets,
        "bump-spec-ts": cmd_bump_spec_ts,
        "coverage-check": cmd_coverage_check,
        "count-oqs": cmd_count_oqs,
        "audit": cmd_audit,
        "derive-branch": cmd_derive_branch,
        "worktree-clean": cmd_worktree_clean,
        "worktree-dirty": cmd_worktree_dirty,
        "commit-subject": cmd_commit_subject,
        "mr-title": cmd_mr_title,
        "branch-classify": cmd_branch_classify,
        "requires-clean-tree": cmd_requires_clean_tree,
        "stash-list": cmd_stash_list,
        "stash-stale": cmd_stash_stale,
        "rename-slug": cmd_rename_slug,
    }

    handler = dispatch.get(command)
    if handler:
        return handler(args)

    print(f"Command '{command}' not yet implemented via Python backend.", file=sys.stderr)
    print(f"Currently implemented: {', '.join(dispatch.keys())}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
