# SDD Pipeline

SDD pipeline is at `$OPEN_SDD_ROOT`.

Load `$OPEN_SDD_ROOT/agent/PIPELINE.md` for the full
pipeline protocol (gates, spec template, stack detection, OQ rules).

If `.opensdd/service-rules.md` exists, load it for project-specific
invariants (business rules, fallback behavior, architecture constraints).

## Core Rules

- Never silently infer missing business behavior.
- Create Open Questions for ambiguous behavior.
- BLOCKING Open Questions stop progression.

## Scope

- Keep changes minimal and localized.
- Do not modify unrelated files.
- Avoid broad repository scans unless requested.
- Prefer existing patterns unless a significant issue exists.

## Critical Review

Identify issues likely to:
- break behavior
- violate business rules
- create data inconsistency
- affect contracts
- create cross-service regressions
- introduce security or transaction risks

Avoid optional refactors or redesigns.

## Findings Severity

- BLOCKING → stop progression
- IMPORTANT → warn only
- OPTIONAL → non-critical improvements

## Open Questions

Create only for:
- ambiguous behavior
- missing dependencies
- conflicting rules/contracts
- unsafe implementation conditions

Do not create for:
- optional refactors
- stylistic preferences
- speculative improvements

## State

- Service invariants: `.opensdd/service-rules.md`
- Feature state: `.specwork/`
- Prefer `.specwork/_state/*.json`

## Testing

- New classes, enums, and DTOs require dedicated test classes.
- Prefer focused regression tests for changed logic.
- New endpoints require integration test coverage.
- Avoid full test suites unless requested.

## Quality Gates

- `bash commands/check.sh` must pass before pushing (`/f-mr`). It is not required before committing — `/f-commit` does not run it.
- SDD pipeline ships a stack-detecting default at `$OPEN_SDD_ROOT/commands/check.sh` (auto-detects Gradle / Maven / npm / pnpm / yarn / pytest / Cargo / Go). The framework runs that script by default — no setup needed for the common case.
- To override (e.g. Spring Boot with `integrationTest`, Maven with profiles, extra lint steps), drop a project-local `commands/check.sh` in the project root. `/f-mr` prefers it over the framework default. Template lives at `$OPEN_SDD_ROOT/templates/check.sh.example`.
- Failed quality checks block progression — do not push on failure. `/f-mr` may run a guarded repair loop (max 3 attempts, counted by `mr.sh`; never edits `check.sh`, test configs or existing tests) before giving up.

## Command mappings

| Pattern | Action |
|---------|--------|
| `/f-start <args>` | `bash $OPEN_SDD_ROOT/commands/start.sh <args>` |
| `/f-plan` | `bash $OPEN_SDD_ROOT/commands/plan.sh` |
| `/f-implement` | `bash $OPEN_SDD_ROOT/commands/implement.sh` |
| `/f-implement --done N` | `bash $OPEN_SDD_ROOT/commands/implement.sh --done N` |
| `/f-pause` | `bash $OPEN_SDD_ROOT/commands/pause.sh` |
| `/f-resume` | `bash $OPEN_SDD_ROOT/commands/resume.sh` |
| `/f-status` | `bash $OPEN_SDD_ROOT/commands/status.sh` |
| `/f-test-design` | `bash $OPEN_SDD_ROOT/commands/test-design.sh` |
| `/f-test-impl` | `bash $OPEN_SDD_ROOT/commands/test-impl.sh` |
| `/f-commit` | `bash $OPEN_SDD_ROOT/commands/commit.sh` |
| `/f-auto` | `bash $OPEN_SDD_ROOT/commands/auto.sh` |
| `/f-auto <ticket>` | `bash $OPEN_SDD_ROOT/commands/auto.sh <ticket>` |
| `/f-spec` | `bash $OPEN_SDD_ROOT/commands/spec.sh` |
| `/f-spec <args>` | `bash $OPEN_SDD_ROOT/commands/spec.sh <args>` |
| `/f-spec --tier <tier> "<reason>"` | `bash $OPEN_SDD_ROOT/commands/spec.sh --tier <tier> "<reason>"` (force the triage tier; `auto` drops it) |
| `/f-resync` | `bash $OPEN_SDD_ROOT/commands/resync.sh` |
| `/f-resync --rename-branch <name>` | `bash $OPEN_SDD_ROOT/commands/resync.sh --rename-branch <name>` |
| `/f-code-review` | `bash $OPEN_SDD_ROOT/commands/code-review.sh` |
| `/f-code-review --recheck` | `bash $OPEN_SDD_ROOT/commands/code-review.sh --recheck` |
| `/f-code-review --auditor` | `bash $OPEN_SDD_ROOT/commands/code-review.sh --auditor` (asked for by `/f-commit` on high-risk pipelines) |
| `/f-mr-review <branch\|mr-url\|mr-iid>` | `bash $OPEN_SDD_ROOT/commands/mr-review.sh <arg>` |
| `/f-undo` | `bash $OPEN_SDD_ROOT/commands/undo.sh` (reversible; `--restore` to recover, `--hard --force` to discard) |
| `/f-help` | `bash $OPEN_SDD_ROOT/commands/help.sh` |
| `/f-help overview` | `bash $OPEN_SDD_ROOT/commands/help.sh overview` |
| `/f-mr-address` | `bash $OPEN_SDD_ROOT/commands/mr-address.sh` |
| `/f-handoff` | `bash $OPEN_SDD_ROOT/commands/handoff.sh` |
| `/f-mr` | `bash $OPEN_SDD_ROOT/commands/mr.sh` |
| `/f-close` | `bash $OPEN_SDD_ROOT/commands/close.sh` (re-run with `--promote '<json>'` or `--no-promote` after the rule-promotion pass) |
| `/doc-catalog` | `bash $OPEN_SDD_ROOT/commands/doc-catalog.sh` |
| `/doc-catalog list` | `bash $OPEN_SDD_ROOT/commands/doc-catalog.sh list` |
| `/doc-catalog-query <question>` | `bash $OPEN_SDD_ROOT/commands/doc-catalog-query.sh <question>` |
| `/doc-adr <desc>` | `bash $OPEN_SDD_ROOT/commands/doc-adr.sh <desc>` |
| `/doc-adr open-questions` | `bash $OPEN_SDD_ROOT/commands/doc-adr.sh open-questions` |
| `/doc-adr list` | `bash $OPEN_SDD_ROOT/commands/doc-adr.sh list` |
| `/doc-adr-query <question>` | `bash $OPEN_SDD_ROOT/commands/doc-adr-query.sh <question>` |
| `/doc-spec <path>` | `bash $OPEN_SDD_ROOT/commands/doc-spec.sh <path>` |
| `/doc-spec list` | `bash $OPEN_SDD_ROOT/commands/doc-spec.sh list` |
| `/doc-spec-query <question>` | `bash $OPEN_SDD_ROOT/commands/doc-spec-query.sh <question>` |
| `/doc-investigation` | `bash $OPEN_SDD_ROOT/commands/doc-investigation.sh` |
| `/doc-investigation-query <question>` | `bash $OPEN_SDD_ROOT/commands/doc-investigation-query.sh <question>` |
| `/arch-query <question>` | `bash $OPEN_SDD_ROOT/commands/arch-query.sh <question>` |

All commands run from the root of the current project.
