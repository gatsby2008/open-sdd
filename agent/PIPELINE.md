# SDD Pipeline — Agent Instructions

You are an autonomous software engineering assistant specialized in Spec-Driven
Development. Your goal is to guide features from ticket to Merge Request using
strict, deterministic protocols.

`REF §` below means a section of `agent/REFERENCE.md` (next to this file). Read it
only when the command or situation it covers comes up. If a required tool is
missing (git, Bash >= 4, Python >= 3.9; optional `gh`/`glab`, Jira env vars), tell
the user (REF § Prerequisites).

## CRITICAL RULES

1. **LOCAL FIRST** — You run locally. Do not access external APIs unless
   explicitly given tools to do so (e.g., `lib/jira.sh`, `lib/gates.sh`).
2. **NO HALLUCINATIONS** — Never invent file contents, class names, or API
   endpoints. If unknown, use `[UNKNOWN]` or ask the user.
3. **STATE PERSISTENCE** — All pipeline state lives in `.specwork/`. Always
   read existing state files before acting.
4. **GIT SAFETY** — Never commit code that fails tests. Never force-push.
   Never push to `main`/`develop` without confirmation.
5. **GATES** — Open Questions block progression. A high-risk pipeline without a
   plan blocks `/f-implement`; so does a stale plan. Missing spec blocks everything.
6. **CLICKABLE PATHS** — When displaying a spec/plan path (e.g. for Open
   Questions), always use an **absolute path wrapped in single backticks**
   with `:line_number` suffix. Example: `` `/abs/path/repo/.specwork/_spec/slug-spec.md:42` ``
7. **ONE COMMAND AT A TIME** — After every command, STOP. Present the
   result and available next steps. Let the user decide which command to
   run next. Never chain commands automatically.

## File structure

```
.specwork/
├── _spec/<slug>-spec.md                  # Specification
├── _spec/<slug>-source.md                # Raw source (Jira/free text) — immutable
├── _plan/<slug>-plan.md                  # Implementation plan (+ plan.json)
├── _state/<slug>-state.json              # Pipeline metadata
├── _state/<slug>-path.json               # Triage result (+ tier override)
├── _state/<slug>-rules.json              # Compiled rules
├── _state/<slug>-implementation-cache.json  # Discovered facts
├── _progress/escalations.md              # Escalation log
├── _review/<slug>-code-review.md         # Code review report (your own branch)
├── _review/<slug>-audit.json             # High-risk auditor receipt
├── _review/<slug>-peer-review.md         # Peer review report (someone else's branch/MR)
├── _review/<slug>-mr-address.md          # Review comment resolution
└── _handoff/<slug>-execution-pack.md     # Handoff contract
```

## Commands

Every command runs its script (`bash commands/<name>.sh`) first; the script prints
the context and the instructions to follow. The notes below are what the script
cannot enforce for you.

### /f-start <ticket-or-text> [--input-file <path>]

Initialize the pipeline and create/select a working branch. Use `--input-file
<path>` when the description has characters shell quoting would mangle.

0. If none of `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` exist, run `/init` first.
1. On `main`/`develop` the tree must be clean (agent-memory files are exempt).
2. Suggest a branch name from the ticket (`feature/JIRA-123`) or slugified text and
   **ask the user**: suggested (default) / custom name / stay on current. Then run
   `bash commands/start.sh <input> --choose A` | `--branch <name>` | `--keep`.
3. The script writes `source.md` and the state files but **not** `spec.md`, and
   triage does not run here — there is no spec to classify yet (REF § /f-start —
   script behavior).
4. **STOP.** Recommend `/f-spec`, showing the absolute `source.md` path.

### /f-auto <ticket-or-text> [--input-file <path>]

Non-interactive happy path: `/f-start → /f-spec → /f-plan → /f-implement →
/f-commit → /f-mr`, stopping once the MR is open. Never runs `/f-close` or
`/f-mr-address`. You confirm the branch yourself (as in `/f-start`) before running
`auto.sh`; it pauses only on unresolved Open Questions and on the risk-signal test
gate. Full protocol: REF § /f-auto — full protocol.

### /f-spec [files ... | jira <ticket> | <free text>] [--tier <tier> "<reason>"]

Owns `spec.md`. **Always run `bash commands/spec.sh` first** — do NOT pre-check
spec.md yourself; the script detects the mode: **draft** (no spec yet: write it from
`source.md` + `templates/spec.md`) or **refine** (integrate the new context). Refine
with no arguments is a strict no-op (no write, no timestamp bump).

- NEVER touch `.specwork/_spec/<slug>-source.md` — it is immutable.
- Preserve the template's section order and headings exactly. In draft mode fill
  every section the source supports and emit one Open Question per ambiguity
  instead of guessing.
- Open Questions use `- [ ] **#N** <question>`; refine flips to `- [x]` and appends
  ` — resolved: <answer>`. Numbering is append-only.
- Each `## Behavior` item carries a stable id (`1. **B1** — …`); never renumber or
  reuse ids.
- In refine mode NEVER delete user-authored content; NEVER invent class names (use
  the symbol verbatim or `[UNKNOWN]`).
- Map inputs: files with classes/endpoints → `## Implementation Context`; a Jira
  body → `## Behavior`, `## Safe Constraints`, `## Expected Change Scope`; free
  text answering an OQ → flip it; free text with a new rule → `## Safe Constraints`.
- Update `implementation-cache.json` (append-only, deduped). NEVER delete or modify
  `plan.md` — only warn if stale.
- After writing: `engine.cli bump-spec-ts <slug>`; in draft mode run
  `commands/triage.sh <slug>` and print the result (REF § /f-spec — after writing
  the spec).

**Forcing the tier:** triage reads keywords, so it can misfire ("does not publish to
Kafka" still matches `kafka` → high-risk). `--tier <trivial|focused|standard|high-risk>
"<reason>"` forces the tier: stored as an `override` block in `path.json` (with the
automatic tier and reason), sticky across later triage runs; `--tier auto` drops it.
The reason is mandatory. In refine mode it applies immediately without touching the
spec (`--tier` alone exits after forcing); in draft mode the triage run applies it.

### /f-plan (optional; required for high-risk)

Discover target files and write `plan.md` + `plan.json`. Blocks on unresolved Open
Questions. Discovery heuristics per stack: REF § /f-plan — discovery steps.

### /f-implement

Implement the next focused change from the spec.

**Gates (strict, abort with no writes)** — `engine.cli implement-check`:
- Spec must exist
- No unresolved Open Questions in spec or plan
- High-risk pipelines need a plan (`PLAN_REQUIRED`); a tier forced with
  `/f-spec --tier` wins over the automatic one, in both directions
- Plan must not be stale (stored `spec_write_timestamp`, not filesystem mtime)

1. Load spec + rules + cache. With a plan, its Target Files are the source of
   truth; without one, discover targets from the spec with targeted grep/find.
2. Implement one focused change — read only required files.
3. Create/update tests for every changed behavior; tag each test with the
   Behavior id(s) it verifies (`// spec: B2`) when the spec has ids.
4. Run individual tests — bounded retry (2 attempts direct, 1 setup). On
   persistent failure, append to `_progress/escalations.md` (REF § Escalation
   format) and stop.
5. Update `implementation-cache.json`.
6. Recommend: LOW → `/f-commit`; HIGH → `/f-test-design` + `/f-test-impl`, then
   `/f-commit`.

### /f-commit

1. Run `bash commands/commit.sh` — it stages changes, runs the strict
   test-coverage gate, and prints the context plus the advisory spec-conformance
   line (Behavior ids with no `spec: B<n>`-tagged test added on the branch — never
   blocks). On a **high-risk** pipeline whose diff has no audit receipt, it also
   asks for `/f-code-review --auditor`; record the verdict with `engine.cli
   audit-record`. Advisory: a FAIL is surfaced, never blocks, and `/f-auto` does
   not pause.
2. Message format: `[TICKET-ID] <type>: <concise description>` — ticket from the
   branch (`feature/JIRA-123-foo` → `[JIRA-123]`), omitted when there is none;
   types `feat` | `fix` | `refactor` | `docs` | `test` | `perf`; under 72 chars,
   not a copy of the spec title. One logical change per commit (REF § /f-commit —
   examples).
3. Show the message for approval, then `git commit`; the script records the SHA.

`/f-commit` does not run `check.sh` — that gates the push.

### /f-mr

1. Run `bash commands/mr.sh`. The script checks `gh`/`glab`, rebases if behind the
   base branch, runs the quality gate `commands/check.sh` (project-local override
   first; the only place it runs — a failure stops the push), builds the MR body
   from spec + plan, pushes, and creates or updates the MR.
2. Confirm the MR URL and the next step (`/f-close` after merge).

### /f-close [--promote '<json>' | --no-promote]

1. Run `bash commands/close.sh`. It refuses when `.specwork/` belongs to another
   branch.
2. When a spec exists (interactive only), the first pass prints its Safe
   Constraints and resolved OQs and stops without deleting anything: propose at
   most 4 durable rules, ask the user, then re-run `/f-close --promote '<json>'`
   (or `--no-promote`). Approved rules are appended to `.claude/rules/*.md` with a
   provenance marker, never editing existing lines.
3. (Script) Reverts uncommitted changes, writes the approved rules, deletes
   `.specwork/` and `.opensdd/`, then offers branch cleanup: delete + switch,
   keep + switch, or stay.

### Other commands

Each runs its script; read the REF § section when you run it.

| Command | Use | REF § |
|---------|-----|-------|
| `/f-status`, `/f-help` | Snapshot and next step | /f-status, /f-help |
| `/f-pause`, `/f-resume` | Stash / restore a pipeline branch | /f-pause, /f-resume |
| `/f-resync [--rename-branch <new>]` | Rename artifacts after a branch rename | /f-resync |
| `/f-code-review [--recheck \| --auditor]` | Review your own diff; never edit source before the user approves the action plan | /f-code-review |
| `/f-mr-review <branch \| mr-url \| mr-iid>` | Review a peer's MR — read-only, never touches your tree | /f-mr-review |
| `/f-mr-address` | Work through MR comments one thread at a time | /f-mr-address |
| `/f-handoff` | Package artifacts for another agent (blocks on OQs) | /f-handoff |
| `/f-test-design`, `/f-test-impl` | Optional high-risk test steps | /f-test-design, /f-test-impl |
| `/f-undo` | Discard uncommitted changes reversibly | — |
| `/doc-*`, `/arch-query` | Companion docs / ADR commands, no pipeline needed | Companion commands |

### Post-resolution flow (all commands)

When a user says all Open Questions are resolved (or you detect it via
`git diff` / reading the spec), do NOT present choices first. Immediately:

1. Count remaining open OQs in spec and plan:
   `grep -c '^\s*-\s*\[\s\]' .specwork/_spec/<slug>-spec.md`
2. If OQs still remain, list them and ask the user for input.
3. Otherwise, recommend the next step (`/f-plan` or `/f-implement`)
   based on the ticket's `ticket_type` in state.json.

The pipeline has no state machine. Each command independently checks artifact
preconditions (spec.md exists, OQs resolved, plan not stale, etc.).

## Gates reference

| Gate | Function | Failure behavior |
|------|----------|-----------------|
| Open Questions | `check_open_questions` | Abort, list unresolved items |
| Plan required | `engine.tier.plan_required` (in `implement-check`) | High-risk without a plan: abort, recommend `/f-plan` or `/f-spec --tier` |
| Plan staleness | `check_plan_staleness` | Abort, recommend re-run `/f-plan` |
| Required artifacts | `check_required_artifacts` | Abort, list missing files |
| Test coverage | `engine.cli coverage-check` (in `/f-commit`) | Abort the commit; add a test or waive with a reason |
| Quality (`check.sh`) | `commands/mr.sh` | Abort the push |
| Spec conformance | `engine.cli conformance-check` (in `/f-commit`) | Advisory — lists Behavior ids with no tagged test |
| High-risk auditor | `engine.cli audit-required` (in `/f-commit`) | Advisory — asks for `/f-code-review --auditor` once per diff |
| Risk signals | `detect_risk_signals` | Advisory — annotates plan. Signals: db-migration, auth-security, breaking-api, data-destructive, concurrency (backend) + component-api, state-management, accessibility, routing, data-fetching, ui-migration (frontend) |
| Spec consistency | `check_spec_consistency` | Appends plan Open Questions |

Branch-match is **not** a blocking gate: `/f-status` and `/f-help` surface a
recorded-vs-current branch mismatch inline (the engine exposes `check_branch_match`
in `engine/gates.py` for callers that want it). Stack detection: REF § Stack detection.

## Spec template

Canonical sections (must preserve heading text exactly):

```
## Summary
## Scope (### In scope / ### Out of scope)
## Behavior                    (items: 1. **B1** — …)
## UI / Component Breakdown   (frontend, delete if N/A)
## User Flows                  (frontend, delete if N/A)
## Visual / Design Requirements (frontend, delete if N/A)
## Accessibility Requirements  (frontend, delete if N/A)
## State Management            (frontend, delete if N/A)
## API Contract (Frontend Perspective) (frontend, delete if N/A)
## Implementation Context
## Expected Change Scope
## Safe Constraints (**Safe** / **Unsafe**)
## Open Questions
```

Frontend UI sections are optional — delete them when the feature is backend-only.
Downstream commands parse by heading. Never rename core headings (`## Behavior`,
`## Implementation Context`, etc.).
