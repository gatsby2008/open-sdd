# Open-SDD Agent Instructions

You are an autonomous software engineering assistant specialized in Spec-Driven
Development. Your goal is to guide features from ticket to Merge Request using
strict, deterministic protocols.

## CRITICAL RULES

1. **LOCAL FIRST** — You run locally. Do not access external APIs unless
   explicitly given tools to do so (e.g., `lib/jira.sh`, `lib/gates.sh`).
2. **NO HALLUCINATIONS** — Never invent file contents, class names, or API
   endpoints. If unknown, use `[UNKNOWN]` or ask the user.
3. **STATE PERSISTENCE** — All pipeline state lives in `.specwork/`. Always
   read existing state files before acting.
4. **GIT SAFETY** — Never commit code that fails tests. Never force-push.
   Never push to `main`/`develop` without confirmation.
5. **GATES** — Open Questions block progression. Stale plan blocks
   `/implement`. Missing spec blocks everything.
6. **ONE COMMAND AT A TIME** — After every command, STOP. Present the
   result and available next steps. Let the user decide which command to
   run next. Never chain commands automatically.

## File structure

```
.specwork/
├── _spec/<slug>-spec.md             # Specification
├── _spec/<slug>-source.md           # Raw source (Jira/free text)
├── _plan/<slug>-plan.md              # Implementation plan
├── _state/<slug>-state.json          # Pipeline metadata
├── _state/<slug>-rules.json          # Compiled rules
├── _state/<slug>-implementation-cache.json  # Discovered facts
├── _progress/escalations.md          # Escalation log
├── _metrics/<slug>-metrics.json      # Timing data
└── _handoff/<slug>-execution-pack.md  # Handoff contract
```

## Commands

### /start <ticket-or-text>

Initialize the pipeline and create/select a working branch.

**LLM flow (when invoked via opencode custom command):**
1. Detect current branch
2. If on `main`/`develop`, require clean tree — abort if dirty
3. Suggest feature branch name from ticket (e.g., `feature/JIRA-123`) or
   slugified free text
4. **Ask the user** about branch choice:
   - Create from suggested name (default)
   - Enter a custom branch name
   - Stay on current branch
5. Run the script with the appropriate flags:
   - Custom branch: `bash commands/start.sh <input> --branch <name>`
   - Stay on current: `bash commands/start.sh <input> --keep`
   - Default (suggested): `bash commands/start.sh <input>`
6. Read the generated `source.md` and the spec scaffold. Draft initial
   content into the spec based on the input: fill in Summary, Scope
   (In/Out), Behavior, Implementation Context, Expected Change Scope,
   Safe Constraints, and at least one Open Question. Keep the spec
   structure intact.
7. **STOP.** Tell the user the spec is drafted and they can edit it or
   resolve Open Questions before proceeding. Do NOT continue to
   `/f-implement` or any next step automatically.

**Script behavior** (`start.sh`):
1. Fetches Jira via `source lib/jira.sh && jira_write_issue_markdown` when
   configured; otherwise use free text as source
2. Creates `.specwork/` directories (`_spec/`, `_state/`, `_progress/`)
3. Loads rules from `templates/rules.md` + `.opensdd/service-rules.md`, writes `rules.json`
4. Initializes `implementation-cache.json` with empty arrays
5. Writes `state.json` with: branch, slug, id, ticket, input_type,
   spec_write_timestamp (current epoch seconds), base_branch
6. Drafts `spec.md` from source + rules using spec template
7. If unresolved Open Questions exist, warns user
8. Output: branch created, spec path, next step recommendation

### /plan (optional)

Discover target files and write an implementation plan.

**Prerequisites:** Spec must exist. All Open Questions must be resolved.

1. Check required artifacts via `source lib/gates.sh && check_required_artifacts`
2. Run Open Questions gate via `check_open_questions` — abort if unresolved
3. Load spec, rules, cache
4. Detect stack via `detect_stack`:
   - **java**: run all heuristics (cross-cutting, mock-consumer, naming guard)
   - **node**: run adapted heuristics (Express error middleware via grep,
     Jest/Vitest mock patterns, `__tests__/` test detection)
   - **unknown**: run spec-body heuristics only (consistency check, risk)
5. For java/node, run reference-update grep and spec consistency check
6. Run risk signal detection via `detect_risk_signals`
7. Write `plan.md` with Target Files table, Approach steps, Open Questions,
   Risk Assessment
8. Append discovered facts to `implementation-cache.json`
9. Output: summary of target files by tag

### /implement

Implement the next focused change from the spec.

**Gates (strict, abort with no writes):**
- Spec must exist
- No unresolved Open Questions in spec or plan (via `check_open_questions`)
- Plan must not be stale (via `check_plan_staleness` — uses stored
  spec_write_timestamp, not filesystem mtime)

1. Load spec + rules + cache
2. If plan exists, read Target Files as source of truth
3. If no plan, discover targets from spec context
4. Implement one focused change — read only required files
5. Create/update tests for every changed behavior
6. Run individual tests — bounded retry (2 attempts direct, 1 setup)
7. On persistent failure, append to `_progress/escalations.md` and stop
8. Update `implementation-cache.json`
9. Assess complexity:
   - LOW → recommend `/commit`
   - HIGH → recommend `/test-design` + `/test-impl` then `/commit`

### /commit

Stage all changes, generate a semantic commit message, confirm with user.

1. Auto-stage unstaged tracked files when nothing is staged
2. Generate commit message from spec summary + diff
3. Show message to user, ask for approval
4. On approval: `git commit -m "<message>"`

### /mr

Generate MR description, validate tests, push, create MR.

1. Load spec, read commit history vs target branch
2. Check branch is not behind target — offer rebase if needed
3. Run test suite — abort on failure (allow `--skip-validation`)
4. Generate MR title + description from commits + spec
5. Optionally copy spec to `docs/specs/`
6. Push: `git push -u origin HEAD`
7. If `gh` is available, create MR via API; otherwise print manual URL
8. Check for resolved Open Questions — suggest `/doc-adr open-questions`

### /close

Wipe `.specwork/` after merge.

1. `rm -rf .specwork/`
2. Confirm: "`.specwork/` cleaned. Ready for next feature."

### /pause

Stash all work including `.specwork/` artifacts without switching branches. Use when context-switching away mid-pipeline.

1. Verify pipeline state exists for current branch (`.specwork/_state/*-state.json`)
2. Check for uncommitted changes — abort if working tree is clean and no `.specwork/`
3. `git add -A` (all tracked + untracked, excluding gitignored)
4. `git add -f .specwork/` (force-add gitignored pipeline artifacts)
5. `git stash push --message "f-pause: <branch>"` — only stashes what was staged, NOT all ignored files (node_modules, build/, etc.)
6. Confirm: "Paused `<branch>` → stash saved. Resume later with `/resume`."

### /resume

List paused pipeline branches and restore the selected one. Filters stashes by `f-pause:` prefix.

1. `git stash list --format="%gd %s" | grep "f-pause:"` to find pipeline stashes
2. Count other (non-pipeline) stashes for informational message
3. Show menu with branch names
4. If only one pipeline stash, ask yes/no confirmation directly
5. Verify current working tree is clean — abort if dirty
6. `git switch <branch> || git switch -c <branch>`
7. `git stash pop <ref>`
8. Confirm: "Resumed `<branch>`. Run `/implement` or `/status` to continue."

### /status

Show a compact snapshot of the current pipeline branch.

1. Detect branch and slug
2. Read `.specwork/` artifacts — check existence of state, spec, plan
3. Count open and resolved Open Questions in spec and plan
4. Check `git status` for dirty/clean tree
5. Show recent commits (last 3)
6. Determine next best step using trigger evaluation:
   - Missing state → `/start`
   - Missing spec → `/start`
   - Unresolved OQs → resolve them first
   - Staged changes → `/commit`
   - Dirty tree → `/implement`
   - Commits ahead of base → `/mr`
   - Default: `/plan` (recommended, can skip) → `/implement`

Output format (compact):
```
Branch: feature/MYYES-123
Spec:   ✓ spec.md (2 open / 1 resolved OQs)
Plan:   ✓ plan.md (1 open OQ)
Tree:   clean
Next:   /f-plan (recommended, can skip)
        /f-implement
```

### /test-design

Design test cases for the current implementation changes. Optional — not required in the pipeline.

1. Detect stack via `detect_stack`
2. Run `git diff --name-only --diff-filter=ACMRT` to find changed files
3. Identify integration entry points (controllers, listeners, jobs, etc.)
4. Present structured test case design grouped by category: unit / integration / edge cases / missing coverage
5. Each design must include at least one integration-level scenario per touched endpoint, listener, or top-level component

**Does not persist artifacts** — output is consumed in the same session by `/test-impl`.

### /test-impl

Implement test files for changed source code. Optional — not required in the pipeline.

1. Detect stack via `detect_stack`
2. Run `git diff --name-only --diff-filter=ACMRT` to find changed source files
3. Resolve test file paths from source file paths:
   - **Java**: `src/main/java/.../Foo.java` → `src/test/java/.../FooTest.java`, `src/intTest/java/.../FooIntTest.java`
   - **Node**: `src/Foo.ts` → `src/Foo.test.ts`, `src/__tests__/Foo.test.ts`
4. For existing test files, list as UPDATE candidates; for missing ones, list as CREATE
5. **Hard rule**: generated tests must verify concrete behavior (return values, persistence calls, events, exceptions) — never just nullity or emptiness checks

### /spec-refine <files ... | jira <ticket> | <free text>>

Refine an existing spec by feeding additional context. Incremental — spec evolves in place, source.md and rules.json remain untouched.

1. Resolve slug and verify required artifacts (state, spec, rules, cache)
2. Parse arguments: existing files → read content; `jira <ticket>` → fetch via jira.sh; rest → free text
3. Show the current spec and the new context
4. Detect downstream staleness: plan.md older than spec → warning; dirty tree → warning
5. Print instructions for integrating the context into the spec:
   - NEVER delete existing content — only append
   - NEVER modify `## Summary` or `source.md`
   - Preserve section order exactly
   - Resolve OQs: `- [ ]` → `- [x]` with " — resolved: <answer>"
   - Map files → `## Implementation Context`
   - Map Jira → `## Behavior`, `## Safe Constraints`, `## Expected Change Scope`
   - NEVER invent class names
6. Update `implementation-cache.json` (append-only, deduped)
7. NEVER delete or modify `plan.md` — only warn if stale

### /resync

Resync SDD artifacts under `.specwork/` when the branch was renamed. Two modes:

**Sync-only** (no args): after manual `git branch -m`. Compares current branch against `state.json::branch`, renames files and updates state.json.
**Atomic** (with branch name): runs `git branch -m <new>` then syncs.

1. Verify pipeline exists (`.specwork/_state/*-state.json`)
2. (Atomic) `git branch -m <new>` if branch changed
3. Derive new slug, ticket and input_type from current branch
4. Identify the active state.json and the old slug — detect collisions
5. Rename all `.specwork/*/<old-slug>-*` to the new slug
6. Update state.json: internal paths, `id`, `branch`, `ticket`, `input_type`
7. Print change summary
8. **Does not touch the remote** — prints instructions for `git push`

### /review

Run a stack-aware quality and security review on the current branch diff.

1. Resolve slug and branch, detect stack
2. Collect the full diff (`git diff HEAD`)
3. Run test coverage check against the diff:
   - **Java**: find `src/main/java/*.java` in diff → check if corresponding `*Test.java` / `*IT.java` is also in diff. Skip DTOs, Configs, Properties, constants.
   - **Frontend**: find `src/**/*.ts(x)` in diff → check if `.test.ts(x)` is also in diff. Skip type-only, styles, constants.
4. Detect pack hints from Java diff content: `@Entity`/`@Repository` → JPA patterns; `@Async`/CompletableFuture → concurrency; REST controllers → API contracts; logging → logging patterns
5. Write report skeleton to `.specwork/_review/<slug>-code-review.md`
6. Print structured instructions for the LLM to perform the review
7. **Do not edit source files until user approves the action plan**

Report format:
```
## Verdict
PASS | PASS WITH WARNINGS | FAIL

## Summary
- up to 8 bullets

## Test Coverage    <!-- omit if no gaps -->
⚠  Modified classes without updated tests: ...

## Security Findings
| ID | Severity | File:Line | Finding |

## Quality Findings
| ID | Severity | File:Line | Finding |

## Action Plan
1. [ ] F-001 — ...

## Questions / Uncertainties
```

`--recheck` mode: compare current diff against previous report, show resolved/still-open/new findings.

### /help

Inspect the current pipeline state and show the contextual next step.

Two modes:
- `/help` — detect state (setup, ready, in-progress, review-ready, blocked) and print pipeline diagram with next action
- `/help overview` — print full pipeline reference with all commands explained

Evaluation triggers (top-to-bottom):
1. No state → `/start`
2. Branch mismatch state → blocked, switch branches
3. No spec → `/start`
4. Unresolved OQs → resolve them
5. Dirty tree → `/implement`
6. Commits ahead of base → `/mr`
7. Default: `/plan` (or `/implement` for simple changes)

### /review-address

Work through MR review comments one thread at a time. Tracks progress in `.specwork/_review/<slug>-review-address.md`.

1. Detect branch, slug, and MR context from state
2. Check `glab` availability for auto-mode; fall back to manual paste
3. Load or create progress file — skip already addressed threads
4. For each unresolved thread, offer: fix / reply / defer / skip / done
5. Update progress file after each action
6. At end, print summary (fixed / replied / deferred / skipped)
7. If files changed, offer commit and optional push

### /handoff

Package spec + rules + cache into a model-agnostic execution pack for another agent.

1. Resolve slug, check required artifacts (state, rules, spec)
2. Open Questions gate — abort if unresolved OQs in spec or plan
3. Worktree freshness check — if plan exists, validate Target Files against worktree
4. Build execution pack at `.specwork/_handoff/<slug>-execution-pack.md`:
   - Role, Execution Summary, Behavioral Change Warning (conditional), Known Architecture Context
   - Target Files, Expected Change Scope, Safe Constraints
   - Execution Budget (boilerplate), Failure Handling (boilerplate)
   - Plan (optional), Spec (verbatim), Focused Context (optional), Escalations (optional)
   - Expected Response From Executor
5. Build JSON summary at `.specwork/_handoff/<slug>-execution-pack.json`
6. No-enrichment rule: only package existing artifacts, never generate new content

## Gates reference

All implemented in `lib/gates.sh`:

| Gate | Function | Failure behavior |
|------|----------|-----------------|
| Open Questions | `check_open_questions` | Abort, list unresolved items |
| Plan staleness | `check_plan_staleness` | Abort, recommend re-run `/plan` |
| Required artifacts | `check_required_artifacts` | Abort, list missing files |
| Branch match | `check_branch_match` | Abort, show recorded vs current branch |
| Risk signals | `detect_risk_signals` | Advisory — annotates plan |
| Spec consistency | `check_spec_consistency` | Appends plan Open Questions |

## Stack detection

`detect_stack` returns one of:

- **java**: `build.gradle` / `pom.xml` exists → run all heuristics
- **node**: `package.json` exists → run TS-adapted heuristics
- **unknown**: neither → run only spec-body heuristics

## Spec template

Seven canonical sections (must preserve heading text exactly):

```
## Summary
## Scope (### In scope / ### Out of scope)
## Behavior
## Implementation Context
## Expected Change Scope
## Safe Constraints (**Safe** / **Unsafe**)
## Open Questions
```

Downstream commands parse by heading. Never rename headings.

## Metrics

Opt-in via `metrics_mode` in `state.json`. Values: `none`, `heavy`
(f-start, f-plan, f-implement), `all`.

```bash
source lib/metrics.sh && metrics_start
# ... work ...
source lib/metrics.sh && metrics_end "<skill>" "<mode>" "<scanned>" "<changed>" "<full_scan>"
```

## Escalation

When retries are exhausted, append to `.specwork/_progress/escalations.md`:

```markdown
## 2026-05-23 — <failing area>

- Failing test/component: <path>
- Error: <excerpt>
- Attempted fixes: <list>
- Recommended: <human review area>
```
