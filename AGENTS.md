# SDD Pipeline — open-sdd

open-sdd is at `~/team/Yield/open-sdd/`.

Load `~/team/Yield/open-sdd/agent/SDD_AGENT_INSTRUCTIONS.md` for the full
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
| `/f-start <args>` | `bash ~/team/Yield/open-sdd/commands/start.sh <args>` |
| `/f-plan` | `bash ~/team/Yield/open-sdd/commands/plan.sh` |
| `/f-implement` | `bash ~/team/Yield/open-sdd/commands/implement.sh` |
| `/f-implement --done N` | `bash ~/team/Yield/open-sdd/commands/implement.sh --done N` |
| `/f-pause` | `bash ~/team/Yield/open-sdd/commands/pause.sh` |
| `/f-resume` | `bash ~/team/Yield/open-sdd/commands/resume.sh` |
| `/f-status` | `bash ~/team/Yield/open-sdd/commands/status.sh` |
| `/f-test-design` | `bash ~/team/Yield/open-sdd/commands/test-design.sh` |
| `/f-test-impl` | `bash ~/team/Yield/open-sdd/commands/test-impl.sh` |
| `/f-commit` | `bash ~/team/Yield/open-sdd/commands/commit.sh` |
| `/f-spec-refine <args>` | `bash ~/team/Yield/open-sdd/commands/refine.sh <args>` |
| `/f-resync` | `bash ~/team/Yield/open-sdd/commands/resync.sh` |
| `/f-resync <name>` | `bash ~/team/Yield/open-sdd/commands/resync.sh <name>` |
| `/f-code-review` | `bash ~/team/Yield/open-sdd/commands/code-review.sh` |
| `/f-code-review --recheck` | `bash ~/team/Yield/open-sdd/commands/code-review.sh --recheck` |
| `/f-help` | `bash ~/team/Yield/open-sdd/commands/help.sh` |
| `/f-help overview` | `bash ~/team/Yield/open-sdd/commands/help.sh overview` |
| `/f-review-address` | `bash ~/team/Yield/open-sdd/commands/review-address.sh` |
| `/f-handoff` | `bash ~/team/Yield/open-sdd/commands/handoff.sh` |
| `/f-mr` | `bash ~/team/Yield/open-sdd/commands/mr.sh` |
| `/f-close` | `bash ~/team/Yield/open-sdd/commands/close.sh` | Scorch-earth: revert changes, delete `.specwork/`, optionally delete branch |

All commands run from the root of the current project.
