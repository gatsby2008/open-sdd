# SDD Pipeline — Reference (on demand)

Detail that `agent/PIPELINE.md` points to with **REF §**. Read a section only
when the command or situation it covers comes up — `PIPELINE.md` holds
everything every command needs.

## Prerequisites

The pipeline needs these tools installed:
- **git** >= 2.x
- **Bash** >= 4.x
- **Python** >= 3.9
- **(Optional) GitHub CLI (`gh`)** — enables automatic MR creation and merge checks
- **(Optional) GitLab CLI (`glab`)** — enables automatic MR creation on GitLab
- **(Optional) Jira env vars** (`JIRA_BASE_URL`, `JIRA_USER`, `JIRA_TOKEN`) — enables auto ticket fetching in `/f-start`

For Windows: the pipeline works under WSL2 (recommended) or Git Bash. If the user is on Windows and gets bash errors, recommend WSL2.

The project's own toolchain (e.g., Java + Gradle for Spring Boot, Node.js + npm for frontend) is required by the `check.sh` quality gate (run by `/f-mr` before pushing) and is auto-detected.

## /f-start — script behavior

1. Fetches Jira via `source lib/jira.sh && jira_write_issue_markdown` when
   configured; otherwise use free text as source
2. Creates `.specwork/` directories (`_spec/`, `_state/`, `_progress/`)
2a. Ensures `.specwork/` is in `.gitignore` (appends or creates). Warns if any
    `.specwork/*` files are already tracked from a prior bad setup, with the
    exact `git rm --cached` command to untrack them.
3. Loads rules from `templates/rules.md` + `.opensdd/service-rules.md`, writes `rules.json`
4. Initializes `implementation-cache.json` with empty arrays
5. Writes `state.json` with: branch, slug, id, ticket, input_type,
   spec_write_timestamp (current epoch seconds), base_branch.
   No `current_step` — the pipeline is artifact-driven.
6. **Does NOT create `spec.md`.** That is `/f-spec`'s job — kept separate
   so each command owns one artifact (start = source, spec = spec, plan
   = plan, implement = code).
7. Output: branch created, source.md path, recommend `/f-spec` as next step

## /f-auto — full protocol

Non-interactive driver for the happy path. Chains `/f-start → /f-spec → /f-plan →
/f-implement → /f-commit → /f-mr` non-interactively, then stops once the MR is open. It
never runs `/f-close` or `/f-mr-address`.

When the description contains special characters (JSON, quotes, etc.) that would
be mangled by shell quoting, use `--input-file <path>` to pass the description
from a file instead. The agent writes the file (handling any content) and passes
the path — no quoting issues.

**Branch confirmation is delegated to `/f-start`, and `/f-start` always confirms the
branch name — including under `/f-auto`.** The bash prompt in `start.sh` only fires
when a human runs the script in an interactive terminal (it is gated on a TTY).
When *you* (the agent) drive `/f-auto`, there is no TTY, so the bash `read` cannot
capture your input — you must do the branch confirmation yourself, exactly as in
the `/f-start` flow, **before** invoking `auto.sh`.

**Flow:**
1. **Pipeline check.** Run `PYTHONPATH=. python3 -m engine.cli precheck`.
   - If it **succeeds** (a pipeline is already active here), skip straight to
     step 3 — do NOT re-ask the branch or re-run `/f-start`.
   - If it **fails** (fresh start), continue to step 2.
2. **Branch confirmation (the `/f-start` ask).** Suggest the feature branch name
   from the ticket/slug and ask the user: create suggested (default) / custom
   name / stay on current. Then run `/f-start` with the chosen flag so the branch
   exists before the chain begins:
   - Default (suggested): `bash commands/start.sh <input> --choose A`
   - Custom branch: `bash commands/start.sh <input> --branch <name>`
   - Stay on current: `bash commands/start.sh <input> --keep`
   This writes `source.md` + state and creates/selects the branch.
3. **Run the chain.** Run `bash commands/auto.sh <input>`. Because the pipeline
   is now active, `auto.sh`'s own `precheck` detects it and **skips its internal
   `/f-start`** — so the branch you just confirmed is kept and there is no second
   prompt. `auto.sh` then runs spec → Open-Questions gate → plan → implement and
   returns control to you.
4. **Finish the run (no stop at commit).** After `auto.sh` returns:
   - If `auto.sh` flagged **risk signals**, STOP and ask the user whether to run
     the optional `/f-test-design` + `/f-test-impl` steps (token-costly) before
     committing. With **no** risk signals, do **not** pause here.
   - Then run `/f-commit` then `/f-mr` (commit auto-continues to `/f-mr` via
     pipeline state) and **STOP at the open MR**. If `/f-mr` prints a
     `REPAIR LOOP` block, run the repair loop without asking (§ /f-mr — repair
     loop); still red after 3 attempts → stop without pushing.

   So the run pauses for the human in only two cases: unresolved Open Questions
   (after `/f-spec`, a hard stop) and the risk-signal test gate (after
   `/f-implement`). It never stops at `/f-commit`. Never run `/f-close` or
   `/f-mr-address` yourself.

(If a human runs `bash commands/auto.sh <input>` directly in a terminal instead
of going through you, `start.sh`'s interactive A/B/C prompt — which fires when no
`--choose/--branch/--keep` flag is passed and stdin is a terminal — covers the
branch confirmation, so the behavior is the same in both paths.)

## /f-plan — discovery steps

Discover target files and write an implementation plan.

**Prerequisites:** Spec must exist. All Open Questions must be resolved.

1. Check required artifacts via `source lib/gates.sh && check_required_artifacts`
2. Run Open Questions gate via `check_open_questions` — abort if unresolved
3. Load spec, rules, cache
4. Detect stack via `detect_stack`:
   - **java**: run all heuristics (cross-cutting, mock-consumer, naming guard)
   - **frontend**: run frontend heuristics (error boundaries, Components/Pages/Hooks/Stores mock discovery, `__tests__/` test detection)
   - **node**: run Node backend heuristics (Express error middleware via grep,
     NestJS exception filters, Jest/Vitest mock patterns, `__tests__/` test detection)
   - **unknown**: run spec-body heuristics only (consistency check, risk)
5. For java/node/frontend, run reference-update grep and spec consistency check
6. Run risk signal detection via `detect_risk_signals`
7. Write `plan.md` (human-readable: Target Files table, Approach steps, Open
   Questions, Risk Assessment) and `plan.json` (machine-readable companion:
   Target Files + per-target progress, consumed by `/f-implement` and `/f-mr`)
8. Append discovered facts to `implementation-cache.json`
9. Output: summary of target files by tag

## /f-commit — examples

Commit discipline: one logical change per commit. Examples:
```
[JIRA-123] feat: add Flyway migration V23 for consent_flag column
[JIRA-123] feat: add ConsentService with saveConsent logic
[JIRA-123] feat: add ConsentController POST /api/v1/consent
[JIRA-123] test: add unit and integration tests for consent flow
```

## /f-spec — after writing the spec

7. After writing the spec:
    - Bump `spec_write_timestamp`: `engine.cli bump-spec-ts <slug>`
    - **Draft mode only**: run `commands/triage.sh <slug>` to classify
      the ticket and print the result (type, complexity, path, reason).
      Triage reads `## Behavior` and `## Implementation Context`, so it
      can only run after the first draft creates the spec body. `/f-start`
      does not create spec.md at all, so triage has nothing to read until
      `/f-spec` runs in draft mode. Skip triage in refine mode (the ticket
      was already classified on the first draft).
    - **Refine mode**: spec changes don't move the pipeline — they just
      invalidate downstream artifacts. `spec_write_timestamp` is enough;
      `/f-implement`'s staleness gate blocks until `/f-plan` refreshes `plan.md`.
    - **Recommend next step** (both modes): if OQs remain, tell the user
      to resolve them and re-run `/f-spec`. Otherwise, recommend `/f-plan`
      (3+ files / high-risk) or `/f-implement` (small / inline discovery).
      In refine mode where `plan.md` already exists, flag it as stale
      and recommend `/f-plan` first.

## /f-pause

Stash all work including `.specwork/` artifacts without switching branches. Use when context-switching away mid-pipeline.

1. Verify pipeline state exists for current branch (`.specwork/_state/*-state.json`)
2. Check for uncommitted changes — abort if working tree is clean and no `.specwork/`
3. `git add -A` (all tracked + untracked, excluding gitignored)
4. `git add -f .specwork/` (force-add gitignored pipeline artifacts)
5. `git stash push --message "f-pause: <branch>"` — only stashes what was staged, NOT all ignored files (node_modules, build/, etc.)
6. Confirm: "Paused `<branch>` → stash saved. Resume later with `/f-resume`."

## /f-resume

List paused pipeline branches and restore the selected one. Filters stashes by `f-pause:` prefix.

1. `git stash list --format="%gd %s" | grep "f-pause:"` to find pipeline stashes
2. Count other (non-pipeline) stashes for informational message
3. Show menu with branch names
4. If only one pipeline stash, ask yes/no confirmation directly
5. Verify current working tree is clean — abort if dirty
6. `git switch <branch> || git switch -c <branch>`
7. `git stash pop <ref>`
8. Confirm: "Resumed `<branch>`. Run `/f-implement` or `/f-status` to continue."

## /f-status

Show a compact snapshot of the current pipeline branch.

1. Detect branch and slug
2. Read `.specwork/` artifacts — check existence of state, spec, plan
3. Count open and resolved Open Questions in spec and plan
4. Check `git status` for dirty/clean tree
5. Show recent commits (last 3)
6. Determine next best step using trigger evaluation:
   - Missing state → `/f-start`
   - Missing spec → `/f-start`
   - Unresolved OQs → resolve them first
   - Staged changes → `/f-commit`
   - Dirty tree → `/f-implement`
   - Commits ahead of base → `/f-mr`
   - Default: `/f-plan` (recommended, can skip) → `/f-implement`

Output format (compact):
```
Branch: feature/MYYES-123
Spec:   ✓ spec.md (2 open / 1 resolved OQs)
Plan:   ✓ plan.md (1 open OQ)
Tree:   clean
Next:   /f-plan (recommended, can skip)
        /f-implement
```

## /f-test-design

Design test cases for the current implementation changes. Optional — not required in the pipeline.

1. Detect stack via `detect_stack`
2. Run `git diff --name-only --diff-filter=ACMRT` to find changed files
3. Identify integration entry points (controllers, listeners, jobs, etc.)
4. Present structured test case design grouped by category: unit / integration / edge cases / missing coverage
5. Each design must include at least one integration-level scenario per touched endpoint, listener, or top-level component

**Does not persist artifacts** — output is consumed in the same session by `/f-test-impl`.

## /f-test-impl

Implement test files for changed source code. Optional — not required in the pipeline.

1. Detect stack via `detect_stack`
2. Run `git diff --name-only --diff-filter=ACMRT` to find changed source files
3. Resolve test file paths from source file paths:
   - **Java**: `src/main/java/.../Foo.java` → `src/test/java/.../FooTest.java`, `src/intTest/java/.../FooIntTest.java`
   - **Node**: `src/Foo.ts` → `src/Foo.test.ts`, `src/__tests__/Foo.test.ts`
4. For existing test files, list as UPDATE candidates; for missing ones, list as CREATE
5. **Hard rule**: generated tests must verify concrete behavior (return values, persistence calls, events, exceptions) — never just nullity or emptiness checks

## /f-resync

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

## /f-code-review

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

`--auditor` (asked for by `/f-commit` on high-risk pipelines): reviews the branch
diff since the merge-base plus staged changes, report-only — no fix proposals —
and ends with `engine.cli audit-record <slug> "<verdict>"`, so the same diff is
never reviewed twice (receipt: `.specwork/_review/<slug>-audit.json`).

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

## /f-mr — repair loop

A bounded loop against `check.sh`: fix the code, re-check, at most **3 attempts**.
`check.sh` is the metric, so the loop must not be able to edit it. `mr.sh` — the
only command that pushes — holds the loop in code through `engine/repair.py`:
state in the git dir, one file per branch (`.git/open-sdd-repair-<branch>-<hash>.json`,
never committed), a guard re-run on every `/f-mr` run while the loop is open and an
attempt counted whenever the content changed since the last red check (re-running
on the same content is free),
no rebase while it is open, and no push until it closes green. It raises the bar;
it is not tamper-proof (a raw `git push` or `repair-reset` gets past it). State left
by deleted branches is pruned whenever a new loop opens.

The guard rejects: any change to the project's `commands/check.sh` or to a
test-runner config (`pytest.ini`, `conftest.py`, `jest.config.*`, `.mocharc*` …);
an added line that excludes or deselects tests in a build file (`pyproject.toml`,
`package.json`, `pom.xml`, `build.gradle` …); a removed or modified line in an
existing test file; a deleted or renamed test file; an added skip/disable/focus
marker (`@Disabled`, `skipif`, `assumeTrue(`, `it.only(`, `t.Skip(` …). When the
project has no `commands/check.sh` of its own (framework default), only the test
and config rules apply.

**When.** `mr.sh` printed a `REPAIR LOOP` block after a failed pre-push check.
Nothing was pushed. Not offered after a post-rebase failure (`mr.sh` dies there).

**Ask first, unless non-interactive.** Interactive: show the failure and ask
"Try to repair it? (max 3 attempts, without touching check.sh, test configs or
existing tests)". On anything but yes, drop the loop and stop:
`PYTHONPATH=$OPEN_SDD_ROOT python3 -m engine.cli repair-reset`. `/f-auto`
(`SDD_NON_INTERACTIVE=1`): start without asking.

**Each attempt:**

1. Read the `check.sh` output and find the cause (failing test, compile error, lint).
2. Fix the **code**, staying inside the spec (and plan, when present). Allowed:
   production code, and *new* lines or files in tests. Not allowed: anything the
   guard rejects. Never special-case the failing test's inputs in production code
   (`if price == 200: …`) — the guard cannot see that. If the test itself looks
   wrong, or the fix needs a business decision the spec does not settle, stop —
   that is an Open Question, not a repair.
3. Re-run `/f-mr`. It runs the guard and counts the attempt, then the checks:
   - red → a new `REPAIR LOOP` block (next attempt), or "attempts are used" → stop;
   - guard rejection → stop, do not push;
   - green → `NOT PUSHED YET` (rc 1): it lists the paths to commit and the exact
     `git add -- <paths>`. Run it — `/f-commit` only stages tracked files, so a new
     test file would be left out — then commit with `/f-commit` (its coverage gate
     and conformance check apply) and re-run `/f-mr`. The re-run sees the same
     content already passed, skips the re-check, closes the loop and pushes.
     Files that were already untracked when the loop opened (`.DS_Store`, local
     scratch) are ignored by the guard and never block the close. That includes an
     untracked test file: a skip marker it already had before the loop opened is
     not seen — the guard judges only what the repair changes.
   - Re-running on unchanged content costs no attempt, but it does re-run the whole
     check (fresh output, and a flaky test gets its chance) — so do not re-run just
     to read the output again.

**Stopped** (guard rejection or exhausted) → report the reason and the last
failure. The changes stay in the working tree for the user (`/f-undo` discards
them; `repair-reset` drops the loop once a human has reviewed them).

## /f-mr-review

Peer review someone else's committed changes — a branch or a merge request.
Unlike `/f-code-review`, which reviews your working tree, `/f-mr-review` resolves a
remote diff and reviews it without ever touching your working tree.

1. Run `bash commands/mr-review.sh <arg>` — the script classifies the argument
   (MR link / MR IID / branch name), resolves to a diff via `glab` or `git`,
   detects stack from diff paths, runs advisory test-coverage check, and writes a
   report skeleton to `.specwork/_review/<slug>-peer-review.md`
   (or `$HOME/.local/share/sdd/peer-reviews/<slug>-<date>.md`).
2. The script prints the review instructions, stack routing, pack hints, and the
   full diff.
3. Perform the review using the same engine as `/f-code-review` — stack-aware
   quality and security review, evidence-based findings with file:line citations.
4. Update the report file with your findings.
5. **Read-only rule**: never checkout, switch branches, commit, push, or comment
   on the MR. This is a peer review — the user takes findings into their review
   by hand.

## /f-help

Inspect the current pipeline state and show the contextual next step.

Two modes:
- `/f-help` — detect state (setup, ready, in-progress, review-ready, blocked) and print pipeline diagram with next action
- `/f-help overview` — print full pipeline reference with all commands explained

Evaluation triggers (top-to-bottom):
1. No state → `/f-start`
2. Branch mismatch state → blocked, switch branches
3. No spec → `/f-start`
4. Unresolved OQs → resolve them
5. Dirty tree → `/f-implement`
6. Commits ahead of base → `/f-mr`
7. Default: `/f-plan` (or `/f-implement` for simple changes)

## /f-mr-address

Work through MR review comments one thread at a time. Tracks progress in `.specwork/_review/<slug>-mr-address.md`.

1. Detect branch, slug, and MR context from state
2. Check `glab` availability for auto-mode; fall back to manual paste
3. Load or create progress file — skip already addressed threads
4. For each unresolved thread, offer: fix / reply / defer / skip / done
5. Update progress file after each action
6. At end, print summary (fixed / replied / deferred / skipped)
7. If files changed, offer commit and optional push

## /f-handoff

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

## Companion commands (Doc / ADR)

Beyond the pipeline, open-sdd registers companion commands for cross-service
documentation and architecture decisions. These are **not** `/f-`-prefixed and run
independently of any active `.specwork/` pipeline. Each maps to a script under
`commands/` — run the script, then act on its output (confirm with the user before
writing files). Suggest them when relevant: e.g. after `/f-mr` resolves Open
Questions worth preserving, recommend `/doc-adr open-questions`.

| Command | Script | What it does |
|---------|--------|--------------|
| `/doc-catalog` | `doc-catalog.sh` | Scan the codebase and store the service catalog in the registry (`list` to inspect) |
| `/doc-catalog-query` | `doc-catalog-query.sh` | Answer cross-service architecture questions across all catalogs |
| `/doc-adr` | `doc-adr.sh` | Create an Architecture Decision Record and store it in the registry (`list` to inspect) |
| `/doc-adr-query` | `doc-adr-query.sh` | Answer architecture-decision questions across all ADRs |
| `/doc-spec` | `doc-spec.sh` | Store a feature spec in the central spec registry (`list` to inspect) |
| `/doc-spec-query` | `doc-spec-query.sh` | Answer feature/spec questions across the spec registry |
| `/doc-investigation` | `doc-investigation.sh` | Capture the current investigation as a structured document (`list` to inspect) |
| `/doc-investigation-query` | `doc-investigation-query.sh` | Answer questions across all captured investigations |
| `/arch-query` | `arch-query.sh` | Query architecture design documents (`$OPEN_SDD_ARCH_HOME`) |

## Stack detection

`detect_stack` returns one of:

- **java**: `build.gradle` / `pom.xml` exists → run all heuristics
- **frontend**: `package.json` + Vite / Next / Angular / Svelte / Nuxt config or framework dep → run frontend-adapted heuristics (components, pages, stores, hooks)
- **node**: `package.json` exists (no frontend framework detected) → run Node backend heuristics (Express/NestJS)
- **unknown**: neither → run only spec-body heuristics

## Escalation format

When retries are exhausted, append to `.specwork/_progress/escalations.md`:

```markdown
## 2026-05-23 — <failing area>

- Failing test/component: <path>
- Error: <excerpt>
- Attempted fixes: <list>
- Recommended: <human review area>
```
