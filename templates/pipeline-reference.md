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

- `bash commands/check.sh` must pass before committing (`/f-commit`) and again before pushing (`/f-mr`).
- SDD pipeline ships a stack-detecting default at `$OPEN_SDD_ROOT/commands/check.sh` (auto-detects Gradle / Maven / npm / pnpm / yarn / pytest / Cargo / Go). The framework runs that script by default — no setup needed for the common case.
- To override (e.g. Spring Boot with `integrationTest`, Maven with profiles, extra lint steps), drop a project-local `commands/check.sh` in the project root. `/f-commit` and `/f-mr` prefer it over the framework default. Template lives at `$OPEN_SDD_ROOT/templates/check.sh.example`.
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
| `/f-auto` | `bash $OPEN_SDD_ROOT/commands/auto.sh` |
| `/f-auto <ticket> [--with-tests]` | `bash $OPEN_SDD_ROOT/commands/auto.sh <ticket> [--with-tests]` |
| `/f-spec` | `bash $OPEN_SDD_ROOT/commands/spec.sh` |
| `/f-spec <args>` | `bash $OPEN_SDD_ROOT/commands/spec.sh <args>` |
| `/f-resync` | `bash $OPEN_SDD_ROOT/commands/resync.sh` |
| `/f-resync <name>` | `bash $OPEN_SDD_ROOT/commands/resync.sh <name>` |
| `/f-code-review` | `bash $OPEN_SDD_ROOT/commands/code-review.sh` |
| `/f-code-review --recheck` | `bash $OPEN_SDD_ROOT/commands/code-review.sh --recheck` |
| `/f-help` | `bash $OPEN_SDD_ROOT/commands/help.sh` |
| `/f-help overview` | `bash $OPEN_SDD_ROOT/commands/help.sh overview` |
| `/f-mr-address` | `bash $OPEN_SDD_ROOT/commands/mr-address.sh` |
| `/f-handoff` | `bash $OPEN_SDD_ROOT/commands/handoff.sh` |
| `/f-mr` | `bash $OPEN_SDD_ROOT/commands/mr.sh` |
| `/f-close` | `bash $OPEN_SDD_ROOT/commands/close.sh` |
| `/doc-catalog` | `bash $OPEN_SDD_ROOT/commands/doc-catalog.sh` |
| `/doc-publish` | `bash $OPEN_SDD_ROOT/commands/doc-publish.sh` |
| `/doc-publish list` | `bash $OPEN_SDD_ROOT/commands/doc-publish.sh list` |
| `/doc-query <question>` | `bash $OPEN_SDD_ROOT/commands/doc-query.sh <question>` |
| `/doc-adr <desc>` | `bash $OPEN_SDD_ROOT/commands/doc-adr.sh <desc>` |
| `/doc-adr open-questions` | `bash $OPEN_SDD_ROOT/commands/doc-adr.sh open-questions` |
| `/adr-publish` | `bash $OPEN_SDD_ROOT/commands/adr-publish.sh` |
| `/adr-publish list` | `bash $OPEN_SDD_ROOT/commands/adr-publish.sh list` |
| `/adr-query <question>` | `bash $OPEN_SDD_ROOT/commands/adr-query.sh <question>` |
| `/doc-freshness` | `bash $OPEN_SDD_ROOT/commands/doc-freshness.sh` — detect drift between docs and code |
| `/doc-freshness <path>` | `bash $OPEN_SDD_ROOT/commands/doc-freshness.sh <path>` — check docs in another repo |
| `/spec-query <question>` | `bash $OPEN_SDD_ROOT/commands/spec-query.sh <question>` — query product specs in registry |
| `/sec-query <question>` | `bash $OPEN_SDD_ROOT/commands/sec-query.sh <question>` — query security docs in registry |

All commands run from the root of the current project.
