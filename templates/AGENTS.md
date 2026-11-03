# AGENTS.md

Project-level guidance for any coding agent working in this repository, including the
Spec-Driven Development (SDD) pipeline from [open-sdd](https://github.com/anomalyco/opencode).

**SDD pipeline protocol:** this repo is wired up to open-sdd. Load
`$OPEN_SDD_ROOT/agent/PIPELINE.md` for the full pipeline protocol (gates, spec template, stack
detection, OQ rules); on-demand detail lives in `agent/REFERENCE.md`.

## Rules (service invariants)

Project-specific, hand-authored rules are resolved from **committed** shared locations, in order:

1. `rules/*.md` — the neutral home (agent-agnostic). Preferred.
2. `.claude/rules/*.md` — legacy home used by projects that predate the agent-neutral layout.
3. `.opensdd/service-rules.md` — per-developer local rules (gitignored), plus the synced copy of
   the shared rules written by `/f-start`.

If any exists, load it for project-specific invariants (business rules, fallback behavior,
architecture constraints) before changing behavior in its area.

## Service Catalog & Knowledge Base

- A catalog of this service (endpoints, SQS/SNS events, integrations) lives at `docs/service-info.md`
  when present. It is **not committed**, so it is often absent — that is normal, **not** a signal to
  generate it. Generate or refresh it **only** when explicitly asked or when a task actually needs it
  (it is a full-codebase scan), via `/doc-catalog` (it writes straight to the central registry — no
  copy in the repo, no separate publish step). Treat any existing copy as possibly stale and verify
  against code.
- Cross-service and cross-cutting questions ("who consumes event X?", "who calls `/api/v1/Y`?", "what
  does service Z depend on?", "why did we add the captcha bypass header?", "have we seen this bug
  before?"): use **`/doc-ask <question>`** — the unified query over the whole registry (catalogs, ADRs,
  specs, and investigations). It grounds every answer in the registry's `raw/` source layer and, where
  a two-layer `wiki/` exists, follows its `[[backlinks]]` for cross-cutting questions. It supersedes
  the older per-registry `*-query` commands. `$OPEN_SDD_DOC_HOME` must point at the registry's `raw/`
  directory (default `~/.claude/` when unset); if it is empty/unset, `/doc-ask` says so.
- Before changing behavior covered by a past decision or spec, check this service's ADRs, specs, and
  investigations via `/doc-ask` so the change doesn't silently contradict them.
- After adding endpoints, SQS/SNS events, Feign clients, or integrations: refresh with `/doc-catalog`.

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

- Service invariants: `rules/` → `.opensdd/service-rules.md`
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
| `/f-resync` | `bash $OPEN_SDD_ROOT/commands/resync.sh` |
| `/f-code-review` | `bash $OPEN_SDD_ROOT/commands/code-review.sh` |
| `/f-code-review --recheck` | `bash $OPEN_SDD_ROOT/commands/code-review.sh --recheck` |
| `/f-code-review --auditor` | `bash $OPEN_SDD_ROOT/commands/code-review.sh --auditor` |
| `/f-mr-review <branch\|mr-url\|mr-iid>` | `bash $OPEN_SDD_ROOT/commands/mr-review.sh <arg>` |
| `/f-undo` | `bash $OPEN_SDD_ROOT/commands/undo.sh` (reversible; `--restore` to recover, `--hard --force` to discard) |
| `/f-help` | `bash $OPEN_SDD_ROOT/commands/help.sh` |
| `/f-mr-address` | `bash $OPEN_SDD_ROOT/commands/mr-address.sh` |
| `/f-handoff` | `bash $OPEN_SDD_ROOT/commands/handoff.sh` |
| `/f-mr` | `bash $OPEN_SDD_ROOT/commands/mr.sh` |
| `/f-close` | `bash $OPEN_SDD_ROOT/commands/close.sh` (re-run with `--promote '<json>'` or `--no-promote` after the rule-promotion pass) |
| `/doc-catalog` | `bash $OPEN_SDD_ROOT/commands/doc-catalog.sh` |
| `/doc-adr <desc>` | `bash $OPEN_SDD_ROOT/commands/doc-adr.sh <desc>` |
| `/doc-spec <path>` | `bash $OPEN_SDD_ROOT/commands/doc-spec.sh <path>` |
| `/doc-investigation` | `bash $OPEN_SDD_ROOT/commands/doc-investigation.sh` |
| `/doc-ask <question>` | `bash $OPEN_SDD_ROOT/commands/doc-ask.sh "<question>"` — one query over catalogs, ADRs, specs and investigations |
| `/doc-ingest [path\|session]` | `bash $OPEN_SDD_ROOT/commands/doc-ingest.sh` — compile `raw/` into the `wiki/` layer |

All commands run from the root of the current project.