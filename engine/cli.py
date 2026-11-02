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
from pathlib import Path
from typing import Optional

from engine.state import load_pipeline_state, save_pipeline_state
from engine.gates import (
    resolve_slug, check_open_questions, check_required_artifacts, check_plan_staleness,
    require_specwork, detect_stack, detect_risk_signals, pipeline_branch_status,
    pipeline_inventory, SPECWORK,
)
from engine.persistence import load_plan, save_plan, load_cache, save_cache


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
    # Usage: triage <slug> [--tier <tier|auto> "<reason>"]. Implementation:
    # engine/triage.py (commands/triage.sh wraps this same entry point).
    if not args:
        print('Usage: cli.py triage <slug> [--tier <tier|auto> "<reason>"]', file=sys.stderr)
        return 1
    slug, rest = args[0], args[1:]
    tier, reason = "", ""
    if rest and rest[0] == "--tier":
        tier = rest[1] if len(rest) > 1 else ""
        reason = " ".join(rest[2:])
    return triage(slug, tier, reason)


def triage(slug: str, tier: str = "", reason: str = "") -> int:
    from engine.triage import run
    return run(slug, tier, reason)


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

    # Plan is optional except on high-risk pipelines (forced tier wins over the
    # automatic one — /f-spec --tier). Elsewhere /f-implement falls back to
    # inline discovery from the spec when plan.json is absent. Staleness only
    # applies when a plan exists.
    from engine.tier import plan_required
    plan = load_plan(slug)
    plan_md = SPECWORK / "_plan" / f"{slug}-plan.md"
    if plan_required(slug) and not plan and not plan_md.exists():
        print("PLAN_REQUIRED")
        return 1
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
    print(detect_stack())
    return 0


def cmd_resolve_slug(args: list[str]) -> int:
    slug = resolve_slug()
    if slug:
        print(slug)
        return 0
    print("COULD_NOT_RESOLVE_SLUG", file=sys.stderr)
    return 1


def cmd_pipeline_branch_status(args: list[str]) -> int:
    # Optional branch arg (mirrors resolve-slug's convention); defaults to the
    # current branch. Prints one JSON object; always exits 0 (reports, never gates) —
    # callers (close.sh) decide what to do with has_any_pipeline/owns_pipeline/
    # is_base_branch themselves.
    branch = args[0] if args else None
    print(json.dumps(pipeline_branch_status(branch)))
    return 0


def cmd_pipeline_inventory(args: list[str]) -> int:
    # Optional branch arg (same convention as pipeline-branch-status); defaults
    # to the current branch. Prints one JSON object; always exits 0 (reports,
    # never gates) — start.sh/status.sh decide what to do with `closable`.
    branch = args[0] if args else None
    print(json.dumps(pipeline_inventory(branch)))
    return 0


def cmd_risk_signals(args: list[str]) -> int:
    # Print the concrete, deterministic risk signals in the spec (one label per
    # line): db-migration, auth-security, breaking-api, data-destructive,
    # concurrency. These are keyword matches, not the fuzzy triage tier — /f-auto
    # uses them to decide whether to pause and ask about the test steps. No
    # signals → no output, rc 0.
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
    from engine.gates import ticket_from_branch, _current_branch
    from engine.slug import slug_from_branch
    branch = args[0] if args else _current_branch()
    if not branch:
        print("COULD_NOT_RESOLVE_BRANCH", file=sys.stderr)
        return 1
    slug = slug_from_branch(branch)
    tkt, itype = ticket_from_branch(branch)
    print(json.dumps({"branch": branch, "slug": slug, "ticket": tkt, "input_type": itype}, indent=2))
    return 0


def cmd_slug(args: list[str]) -> int:
    # Print the slug for a branch (default: current). The one derivation every
    # shell caller uses — start.sh, resync.sh and lib/gates.sh resolve_slug.
    from engine.gates import _current_branch
    from engine.slug import slug_from_branch
    branch = args[0] if args else _current_branch()
    slug = slug_from_branch(branch) if branch else ""
    if not slug:
        print("COULD_NOT_RESOLVE_SLUG", file=sys.stderr)
        return 1
    print(slug)
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
    for ref, branch in stale:
        print(f"{ref}\t{branch}")
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


def cmd_conformance_check(args: list[str]) -> int:
    # Advisory spec-conformance check run by /f-commit: lists the spec's Behavior
    # ids (B1, B2, …) that no test added on this branch tags with `spec: B<n>`.
    # Always rc 0 — reports, never gates; silent for specs without ids.
    from engine.conformance import check
    slug = args[0] if args else resolve_slug()
    return check(slug) if slug else 0


def cmd_promote_apply(args: list[str]) -> int:
    # Append the rules the user approved in /f-close into .claude/rules/*.md,
    # append-only with provenance. All targets are validated before any write.
    # rc 0 = written (or would be, with --dry-run), 1 = rejected, 2 = usage.
    from engine.promote import apply_all
    dry_run = "--dry-run" in args
    args = [a for a in args if a != "--dry-run"]
    if len(args) != 2:
        print("Usage: promote-apply <slug> '<json>' [--dry-run]", file=sys.stderr)
        return 2
    slug, raw = args
    try:
        entries = json.loads(raw)
        if not isinstance(entries, list):
            raise ValueError("expected a JSON list")
    except ValueError as exc:
        print(f"✗ Invalid JSON: {exc}", file=sys.stderr)
        return 2
    try:
        written = apply_all(slug, entries, dry_run=dry_run)
    except ValueError as exc:
        print(f"✗ {exc}", file=sys.stderr)
        return 1
    verb = "Would promote" if dry_run else "Promoted"
    for target, count in written.items():
        print(f"✓ {verb} {count} rule(s) into {target}")
    return 0


def cmd_audit_required(args: list[str]) -> int:
    # High-risk auditor trigger for /f-commit. rc 1 = run /f-code-review
    # --auditor (high-risk pipeline, diff not yet audited); rc 0 = skip — every
    # other tier, an already-audited diff, or any internal error (fails open).
    from engine.audit import audit_required
    slug = args[0] if args else resolve_slug()
    if slug and audit_required(slug):
        print("AUDIT_REQUIRED reason=high-risk")
        return 1
    return 0


def cmd_audit_record(args: list[str]) -> int:
    # Stamp the auditor verdict for the current diff so it is never reviewed
    # twice. Advisory: a FAIL verdict is recorded like any other.
    from engine.audit import record
    if len(args) < 2:
        print("Usage: audit-record <slug> <PASS|PASS WITH WARNINGS|FAIL>", file=sys.stderr)
        return 2
    try:
        record(args[0], " ".join(args[1:]))
    except ValueError as exc:
        print(f"✗ {exc}", file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"⚠ audit receipt not recorded: {exc}", file=sys.stderr)
        return 0
    print("✓ audit receipt recorded")
    return 0


def _repair(cmd):
    # /f-mr repair loop (engine/repair.py): state in the git dir, attempt cap,
    # metric guard. commands/mr.sh drives it; see its docstring for the rcs.
    def handler(args: list[str]) -> int:
        from engine.repair import run
        return run(cmd, args)
    return handler


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


# Single source of truth for supported subcommands. Every entry has a handler;
# COMMANDS is derived from it so the two can never drift. The pipeline's
# user-facing verbs (start, plan, implement, commit, mr, close, …) are handled by
# the commands/*.sh wrappers, NOT here — they are intentionally absent.
def cmd_ask(args: list[str]) -> int:
    # Usage: ask [--budget N] <question> [type:<t>] [service:<s>]. Implementation:
    # engine/registry.py (commands/doc-ask.sh wraps this entry point).
    from engine.registry import ask
    budget = None
    if "--budget" in args:
        i = args.index("--budget")
        try:
            budget = int(args[i + 1])
        except (IndexError, ValueError):
            print("Usage: cli.py ask [--budget N] <question>", file=sys.stderr)
            return 1
        args = args[:i] + args[i + 2:]
    sys.stdout.write(ask(args, budget))
    return 0


DISPATCH = {
    "precheck": cmd_precheck,
    "ask": cmd_ask,
    "triage": cmd_triage,
    "status": cmd_status,
    "check": cmd_check,
    "implement-check": cmd_implement_check,
    "implement-done": cmd_implement_done,
    "implement-plan": cmd_implement_plan,
    "resolve-slug": cmd_resolve_slug,
    "pipeline-branch-status": cmd_pipeline_branch_status,
    "pipeline-inventory": cmd_pipeline_inventory,
    "detect-stack": cmd_detect_stack,
    "risk-signals": cmd_risk_signals,
    "extract-reference-targets": cmd_extract_reference_targets,
    "bump-spec-ts": cmd_bump_spec_ts,
    "coverage-check": cmd_coverage_check,
    "conformance-check": cmd_conformance_check,
    "promote-apply": cmd_promote_apply,
    "audit-required": cmd_audit_required,
    "audit-record": cmd_audit_record,
    "repair-red": _repair("red"),
    "repair-pre": _repair("pre"),
    "repair-green": _repair("green"),
    "repair-reset": _repair("reset"),
    "repair-status": _repair("status"),
    "repair-guard": _repair("guard"),
    "count-oqs": cmd_count_oqs,
    "audit": cmd_audit,
    "derive-branch": cmd_derive_branch,
    "slug": cmd_slug,
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

COMMANDS = list(DISPATCH)


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in DISPATCH:
        print(f"Usage: python3 -m engine.cli <{'|'.join(COMMANDS)}> [args...]")
        print(f"Commands: {', '.join(COMMANDS)}")
        return 1

    return DISPATCH[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
