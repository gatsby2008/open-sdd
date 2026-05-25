# SDD Pipeline — open-sdd

open-sdd is at `$OPEN_SDD_ROOT`.

Load `$OPEN_SDD_ROOT/agent/SDD_AGENT_INSTRUCTIONS.md` for the full
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

- `bash commands/check.sh` must pass before committing (`/f-commit`) and again before pushing (`/f-mr`).
- Failed quality checks block progression — do not commit or push on failure.

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
| `/f-spec-refine <args>` | `bash $OPEN_SDD_ROOT/commands/refine.sh <args>` |
| `/f-resync` | `bash $OPEN_SDD_ROOT/commands/resync.sh` |
| `/f-resync <name>` | `bash $OPEN_SDD_ROOT/commands/resync.sh <name>` |
| `/f-code-review` | `bash $OPEN_SDD_ROOT/commands/code-review.sh` |
| `/f-code-review --recheck` | `bash $OPEN_SDD_ROOT/commands/code-review.sh --recheck` |
| `/f-help` | `bash $OPEN_SDD_ROOT/commands/help.sh` |
| `/f-help overview` | `bash $OPEN_SDD_ROOT/commands/help.sh overview` |
| `/f-review-address` | `bash $OPEN_SDD_ROOT/commands/review-address.sh` |
| `/f-handoff` | `bash $OPEN_SDD_ROOT/commands/handoff.sh` |
| `/f-mr` | `bash $OPEN_SDD_ROOT/commands/mr.sh` |
| `/f-close` | `bash $OPEN_SDD_ROOT/commands/close.sh` |

All commands run from the root of the current project.
