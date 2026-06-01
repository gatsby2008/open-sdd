---
marp: true
theme: default
paginate: true
style: |
  section {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    font-size: 1.1rem;
  }
  h1 { color: #1C1C1C; border-bottom: 3px solid #F5A623; padding-bottom: 0.3em; }
  h2 { color: #2B2B2B; }
  h3 { color: #444444; }
  code { background: #f0f0f0; color: #1C1C1C; padding: 2px 6px; border-radius: 4px; font-size: 0.9em; }
  pre { background: #1C1C1C; color: #e0e0e0; border-radius: 8px; }
  pre code { background: transparent; color: #e0e0e0; font-size: 0.85em; }
  pre .hljs-string { color: #F5A623; }
  pre .hljs-comment { color: #888888; }
  pre .hljs-keyword { color: #E8C97A; }
  pre .hljs-number { color: #F5A623; }
  pre .hljs-built_in { color: #e0e0e0; }
  pre .hljs-section { color: #F5A623; font-weight: bold; }
  pre .hljs-bullet { color: #e0e0e0; }
  pre .hljs-emphasis { color: #e0e0e0; }
  pre .hljs-strong { color: #e0e0e0; }
  pre .hljs-link { color: #F5A623; }
  table { width: 100%; font-size: 0.9em; border-collapse: collapse; }
  th { background: #1C1C1C; color: white; padding: 8px; }
  td { padding: 8px; border-bottom: 1px solid #ddd; }
  .columns { display: grid; grid-template-columns: 1fr 1fr; gap: 2em; }
  section.lead { background: #1C1C1C; color: white; }
  section.lead h1 { color: #F5A623; border-color: #F5A623; }
  section.lead h2 { color: #E8C97A; }
  section.lead p { color: #ccc; }
  section.divider { background: #2B2B2B; color: white; display: flex; align-items: center; }
  section.divider h1 { color: #F5A623; border: none; font-size: 2.5em; }
  section.divider p { color: #aaa; font-size: 1.2em; }
  .note { background: #FFF8E1; border-left: 4px solid #F5A623; padding: 12px 16px; border-radius: 4px; }
  .gate { background: #FFEBEE; border-left: 4px solid #D32F2F; padding: 8px 12px; border-radius: 4px; }
---

<!-- _class: lead -->

# open-sdd

## Spec-Driven Development pipeline

### From ticket to merged MR — with context, without guessing

**Yield Team · 2026**

---

## The problem

```
Jira ticket  →  "I know what to do"  →  code  →  surprise review
```

**What it costs us:**
- Clarifications happen *after* implementation
- Unstructured commits ("fix", "wip", "more changes")
- Empty MR descriptions copied from the last commit
- Tests written at the end, or not at all
- Context switches wipe the mental model of the feature

---

<!-- _class: divider -->

# 01
## What is Spec-Driven Development?

---

## SDD in one sentence

> The spec is the contract. The implementation executes it — it doesn't invent it.

**The cycle:**

```
Spec  →  Plan  →  Implement  →  Test  →  Review  →  MR  →  Close
```

**Key principle:** the person who specifies and the person who implements are the same — just at different moments in time. The spec is the conversation with your future self.

---

## SDD is not bureaucracy

The spec is not a 20-page document. It is a **structured answer to questions you have to answer anyway:**

- What exactly does this feature do?
- What is out of scope?
- Which endpoint/component/service changes?
- What are the acceptance criteria?
- **What don't I know yet?** (Open Questions)

<div class="note">

**Open Questions** are the real value: forcing questions *before* implementing prevents rework when the answers arrive *during* implementation.

</div>

---

## How it differs from other approaches

| Approach | Where the "what" lives |
|----------|------------------------|
| TDD | In tests (`assert expected == actual`) |
| BDD | In tests (`Given / When / Then`) |
| **SDD** | In a natural language design artifact — *before* touching code |

All three complement each other. SDD captures *what* and *why*; TDD/BDD capture *how to verify*.

---

<!-- _class: divider -->

# 02
## Architecture

---

## Two-layer system

```
  ┌────────────────────────────────────────────┐
  │         commands/*.sh  (bash)              │
  │                                            │
  │  I/O, git operations, user interaction     │
  │  One script per /f-* command               │
  └──────────────────┬─────────────────────────┘
                     │ calls
                     ▼
  ┌────────────────────────────────────────────┐
  │         engine/  (Python, stdlib only)      │
  │                                            │
  │  State machine, gates, persistence         │
  │  No side effects on git or filesystem      │
  └────────────────────────────────────────────┘
```

**Why two layers:** bash handles I/O and git; Python handles decisions and data. Each layer is independently testable.

---

## Pipeline state (`.specwork/`)

**Transient, gitignored** — never committed:

```
.specwork/
├── _spec/<slug>-spec.md            # Specification
├── _spec/<slug>-source.md          # Raw input (Jira / free text)
├── _plan/<slug>-plan.md            # Implementation plan
├── _state/<slug>-state.json        # Metadata (branch, slug, timestamps)
├── _state/<slug>-rules.json        # Compiled rules
├── _state/<slug>-implementation-cache.json  # Discovered facts
├── _progress/escalations.md        # Blockers log
├── _test/<slug>-test-design.md     # Test design (high-risk flow)
├── _review/<slug>-code-review.md   # Code review report
├── _review/<slug>-mr-address.md    # Review resolution progress
└── _handoff/<slug>-*-pack.*        # Handoff artifacts
```

**Permanent, committed:** `docs/specs/` (published spec), `docs/adr/` (architecture decisions).

---

## Commands at a glance (19)

```
Pipeline:
  /f-start          Initialize branch + capture source
  /f-spec           Draft or refine the spec
  /f-plan           (optional) Technical plan with target files
  /f-implement      One focused change per run
  /f-commit         Stage + semantic commit
  /f-mr             Push + create/update Merge Request
  /f-close          Clean .specwork/ after merge

Quality:
  /f-code-review    Stack-aware quality + security review
  /f-mr-address     Address review comments thread by thread

High-risk (optional):
  /f-test-design    Design test cases
  /f-test-impl      Implement them

Context:
  /f-pause          Stash everything (including .specwork/)
  /f-resume         Restore a paused feature

Standalone:
  /f-auto           Non-interactive full pipeline → open MR
  /f-help           Where am I, what's next
  /f-status         Detailed pipeline state
  /f-resync         Sync artifacts after branch rename
  /f-handoff        Package artifacts for another agent

Plus companion commands: /doc-adr, /doc-catalog, /doc-publish, /doc-query
```

---

## The pipeline flow

```
  Jira ticket or free-text description
          │
          ▼
    ┌─────────────┐
    │  /f-start   │  → create/select branch, write state + source.md
    │  (/f-auto)  │  → non-interactive alternative; runs through MR
    └──────┬──────┘
           ▼
    ┌─────────────┐
    │  /f-spec    │  → draft (first) or refine (subsequent) the spec
    └──────┬──────┘     bumps spec_write_timestamp; warns if plan gets stale
           │  ◄──── re-run any time to add context, resolve OQs
           ▼
    ┌─────────────┐
    │  /f-plan    │  (optional) → discover targets, draft plan, seed cache
    └──────┬──────┘  re-run after /f-spec to clear staleness
           │
           ▼
    ┌──────────────────────────────────┐
    │  /f-implement (repeat N times)   │
    │                                  │  gates: OQs · stale plan
    │  /f-pause  ·  /f-resume          │  inline tests per step
    └──────────┬───────────────────────┘
               │
       complexity assessment
               │
       ┌───────┴──────────┐
  low/medium           high-risk (optional)
       │                   │
       ▼                   ▼
  /f-commit         /f-test-design
       │             /f-test-impl
       │             /f-commit
       └──────┬──────┘
              │
      ┌───────────────┐
      │ /f-code-review│ (optional)
      └───────┬───────┘
              │
      ┌───────────────┐
      │   /f-mr       │  → push, create MR
      └───────┬───────┘
              │
      ┌───────────────┐
      │ /f-mr-address │  → address review comments
      └───────┬───────┘
              │  merged
      ┌──────────────┐
      │  /f-close    │  → delete .specwork/
      └──────────────┘
```

---

<!-- _class: divider -->

# 03
## Commands in detail

---

### `/f-start <ticket-or-text>`

Initialize the pipeline.

**What it does:**
1. Detects current branch; suggests `feature/JIRA-123` from ticket
2. Chooses a working branch (suggested / custom / stay on current)
3. Fetches Jira ticket (if credentials configured) or uses free text
4. Writes `source.md`, `state.json`, `rules.json`, `implementation-cache.json`
5. **Does NOT create `spec.md`** — that is `/f-spec`'s job
6. Bootstraps `.gitignore` for `.specwork/`

**Output:** `.specwork/_spec/<slug>-source.md`, state files ready

```bash
/f-start MYYES-15535            # with Jira credentials
/f-start "retry logic webhooks" # free text fallback
```

---

### `/f-spec [files | jira <ticket> | free text]`

Draft (first call) or refine (subsequent calls) the specification.

**Two modes, auto-detected by `spec.md` presence:**

| Mode | When | What it does |
|------|------|-------------|
| **Draft** | `spec.md` does not exist | Synthesizes full spec from `source.md` + template + any extra context |
| **Refine** | `spec.md` exists | Integrates new context into existing spec — resolves OQs, expands sections |

**The spec includes:**
- Summary, Scope (in/out), Endpoint/Component, Behavior
- Required Changes, New Configuration, Non-Functional Requirements
- Acceptance Criteria
- **Open Questions** — unresolved `- [ ]` checkboxes that block progression

**Idempotent:** refine mode with no arguments is a strict no-op.

```bash
/f-spec                              # draft mode (first call)
/f-spec "add email case"             # refine: add context
/f-spec jira MYYES-15535             # refine: fetch new ticket data
```

---

### `/f-plan` *(optional)*

Discover target files and write a technical implementation plan.

**What it does:**
1. Checks spec exists and has no unresolved Open Questions
2. Detects stack: `build.gradle`/`pom.xml` → Java, `package.json` → Node
3. Runs heuristics per stack (mock-consumer, naming, reference-update, risk)
4. Writes `plan.md` with Target Files, Approach steps, Risks, Open Questions
5. Seeds `implementation-cache.json`

**When to use:** medium-to-large features (3+ files), refactors with broad blast radius.
**When to skip:** small/obvious changes (1-2 files).

```
Step 1/4  Add Flyway migration V23_add_consent_flag
Step 2/4  Add ConsentRepository.saveConsumerConsent()
Step 3/4  Add ConsentService with business logic
Step 4/4  Add ConsentController POST /api/v1/consent
```

**Gate:** blocks if spec has unresolved Open Questions.

---

### `/f-implement` (repeat N times)

One focused implementation step per run.

**Gates (strict, abort with no writes):**
- Spec must exist
- No unresolved Open Questions (spec or plan)
- Plan must not be stale (spec newer than plan)

**Flow:**
1. Reads spec + plan (or discovers inline if no plan)
2. Shows target files and expected changes
3. You implement the changes inline
4. Runs tests with bounded retry (2 attempts)
5. On persistent failure: writes to `escalations.md`, stops
6. Complexity assessment:
   - **Low** → recommends `/f-commit`
   - **High** → recommends `/f-test-design` + `/f-test-impl`

```bash
/f-implement       # implement the current step
/f-implement --done 3  # mark target #3 as done (shows next target)
```

---

### `/f-commit`

Stage all changes and create one semantic commit.

```bash
/f-commit
```

**What it does:**
1. Stages all tracked changes (`git add -u`)
2. Runs the quality gate: `bash commands/check.sh`
3. Proposes commit message: `[JIRA-123] feat: <spec title>`
4. You approve (or edit, or abort)
5. Updates `state.json` with commit SHA and validation flag

**Format:** `[TICKET-ID] type: concise description` (feat | fix | refactor | docs | test | perf)

**Works on any branch** — no pipeline required for standalone use.

---

### `/f-test-design` + `/f-test-impl` *(optional, high-risk flow)*

Only when the complexity assessment flags high risk.

**`/f-test-design`:**
- Analyzes the diff for test gaps
- Designs integration scenarios per endpoint
- Writes `.specwork/_test/<slug>-test-design.md`

**`/f-test-impl`:**
- Reads the test design artifact
- Resolves test file paths from source paths:
  - `src/main/java/.../Foo.java` → `src/test/java/.../FooTest.java`
  - `src/Foo.ts` → `src/Foo.test.ts` or `src/__tests__/Foo.test.ts`
- Generates test files covering concrete behavior

**Depends on `/f-test-design`** — run in order, or skip both straight to `/f-commit`.

---

### `/f-code-review` *(optional)*

Stack-aware quality and security review of the full branch diff.

**What it checks:**
- Code quality (duplication, naming, error handling)
- Security (injection, auth, secrets)
- Test coverage (modified classes without updated tests)
- Stack-specific patterns (JPA, concurrency, API contracts, logging)

```bash
/f-code-review                    # first review
/f-code-review --recheck          # compare against previous report
```

**Output:** `.specwork/_review/<slug>-code-review.md` with findings severity (Blocker / Major / Minor).

---

### `/f-mr`

Push branch and create or update a Merge Request.

**Pre-flight:**
1. Detects host: `gh` for GitHub, `glab` for GitLab (override with `OPEN_SDD_MR_PROVIDER`)
2. Validates branch is not the default branch and has commits
3. Runs test suite before push — **skips if HEAD was already validated by `/f-commit`**
4. Only pushes if tests pass

**Output:**
- MR title + description built from spec + commits
- Branch pushed to origin
- MR created or updated

```bash
/f-mr           # normal flow
/f-mr --skip-validation  # emergencies only
```

---

### `/f-mr-address`

Address review comments thread by thread.

```
For each comment:
  [f]  Fix the issue → implement + stage + resolve
  [r]  Reply with explanation
  [d]  Defer to a follow-up
  [s]  Skip (not actionable)
```

**Tracks progress** in `.specwork/_review/<slug>-mr-address.md`.
Re-running picks up where it left off.

---

### `/f-close`

Close the feature pipeline after merge.

**What it does:**
1. Checks for dirty tree → prompts to discard or abort
2. Checks MR merge status via `gh` → warns if still open
3. Deletes `.specwork/` (irreversible — asks confirmation)
4. Offers branch cleanup: delete + switch, keep + switch, or stay

<div class="gate">

`/f-close` is always human-driven — it is never reached by `/f-auto`.

</div>

---

<!-- _class: divider -->

# 04
## `/f-auto` — Non-interactive autopilot

---

## `/f-auto <ticket-or-text>`

**Single command** that runs the full pipeline without bash prompts:

```bash
/f-auto MYYES-15535
/f-auto "retry logic for webhooks"
```

**What it executes in sequence:**
1. `/f-start` — creates branch, writes source.md (**confirms branch choice** in interactive TTY sessions)
2. `/f-spec` — drafts the spec from source
3. **Stop if unresolved Open Questions** → alerts and exits
4. `/f-plan` — creates technical plan
5. `/f-implement` — prints spec + plan + target files
6. Hands off to the LLM to implement, then **pauses before commit** for manual review

---

## Autopilot: stops at exactly two points

**1. Unresolved Open Questions** (after `/f-spec`):
```
BLOCKING — Unresolved Open Questions found in spec.
Resolve them, then re-run /f-auto or continue manually.
```

**2. Pre-commit review handoff** (after `/f-implement`):
```
Auto mode paused before /f-commit so you can review changes.
Next: run /f-commit after your review.
```

Auto mode **always** pauses here. Any concrete risk signals found during spec
analysis are surfaced informationally at this handoff to help you decide whether
to run the (costly) `/f-test-design` + `/f-test-impl` steps before committing:

| Risk signal | Keyword matches |
|-------------|----------------|
| `db-migration` | migration, flyway, liquibase, alter table, schema change |
| `auth-security` | authentication, authorization, JWT, OAuth, credentials |
| `breaking-api` | breaking change, remove endpoint, deprecate endpoint |
| `data-destructive` | delete data, purge, production data, truncate |
| `concurrency` | @Transactional, race condition, distributed transaction |

After your manual `/f-commit`, the run auto-opens the MR (`/f-mr`) and stops there.

---

## Autopilot: architectural decisions

**What `/f-auto` does NOT do:**
- ❌ Does NOT commit automatically (pauses before commit for manual review)
- ❌ Does NOT run `/f-close` (post-merge action, deletes your branch)
- ❌ Does NOT run `/f-mr-address` (needs review comments that don't exist yet)
- ❌ Does NOT force test steps (you decide at the pre-commit handoff)

**How it works:**
- Exports `SDD_NON_INTERACTIVE=1` → commands skip routine bash prompts
- `start.sh`: still confirms the branch choice (called with `--confirm-branch`) when the session is interactive (TTY)
- `implement.sh`: auto-re-runs `/f-plan` if stale
- Stops after `/f-implement` and flags `auto_open_mr_after_commit` in state
- `commit.sh`: on your manual `/f-commit`, auto-runs `/f-mr` when that flag is set
- The LLM still implements code changes; only routine bash prompts are skipped

**End state:** changes implemented, working tree paused before commit, `.specwork/` intact.

```
/f-auto  stops here
   │
   ▼
[f-start → spec → plan → impl] ── (human reviews & commits)
                                            │
                                            ▼
                                  commit → mr (auto) → stops
                                            │
                           (human takes over)
                                            ▼
                                   review → merge → close
```

---

<!-- _class: divider -->

# 05
## Gates and quality

---

## The gate system

Every command runs its own pre-flight checks. No central state machine.

```
                 ┌─────────────────┐
                 │  Open Questions │  ← blocks /f-plan, /f-implement, /f-handoff
                 └─────────────────┘

                 ┌─────────────────┐
                 │   Stale plan    │  ← spec newer than plan → re-run /f-plan
                 └─────────────────┘

                 ┌─────────────────┐
                 │ Missing spec    │  ← blocks everything except /f-start, /f-spec
                 └─────────────────┘

                 ┌─────────────────┐
                 │  check.sh       │  ← runs tests before commit and push
                 └─────────────────┘
```

**Staleness is timestamp-based:** `spec_write_timestamp` is stored in `state.json`, not filesystem mtime — survives `git stash` (which destroys mtime).

---

## Open Questions

Unresolved markdown checkboxes **under the `## Open Questions` heading** in `spec.md` (or `plan.md`):

```markdown
## Open Questions

- [ ] Should the consent flag be per-service or global?  ← BLOCKS
- [x] What is the timeout for the external API call?     ← resolved
```

**Rules:**
- Scope-limited: only checkboxes in the `## Open Questions` section count
- `/f-implement` hard-blocks on any unresolved OQ
- `/f-plan` hard-blocks on any unresolved OQ
- `/f-handoff` hard-blocks on any unresolved OQ
- `/f-spec` is the canonical way to add and resolve OQs

---

## Quality gate (`check.sh`)

Every commit and push runs the project's test suite:

| Project has | Command run |
|-------------|-------------|
| `build.gradle` / `build.gradle.kts` | `./gradlew check` |
| `pom.xml` | `mvn verify` |
| `package.json` + `pnpm-lock.yaml` | `pnpm test` |
| `package.json` + `yarn.lock` | `yarn test` |
| `package.json` | `npm test` |
| `Cargo.toml` | `cargo test` |
| `pyproject.toml` / `setup.py` | `pytest` |
| `go.mod` | `go test ./...` |

**Custom override:** drop `commands/check.sh` in the project root for custom validation (integration tests, lint, format).

**Duplicate runs skipped:** `/f-mr` skips the test suite when HEAD was already validated by `/f-commit` (reads `checked_sha` from `state.json`).

---

## Risk signals

**Separate from triage.** Risk signals are deterministic keyword matches — not the fuzzy triage tier.

Detected by `engine risk-signals <slug>`:

| Category | Keywords |
|----------|----------|
| `db-migration` | migration, flyway, liquibase, alter table, schema change |
| `auth-security` | authentication, authorization, JWT, OAuth, credentials |
| `breaking-api` | breaking change, remove endpoint, deprecate endpoint |
| `data-destructive` | delete data, purge, production data |
| `concurrency` | @Transactional, race condition, distributed transaction |

**Purpose:** `/f-auto` uses these to decide whether to pause before commit and ask about the costly test steps. No signal → flow straight through.

---

<!-- _class: divider -->

# 06
## Context switching and utilities

---

## `/f-pause` + `/f-resume`

Save and restore full pipeline state across context switches.

```
f-pause

  git add -A                       # stage all tracked + untracked
  git add -f .specwork/            # force-add gitignored pipeline state
  git stash push -m "f-pause: feature/JIRA-123"

  → switch to any other branch, work on something else

f-resume

  → lists all f-pause stashes with branch names
  → select one → switch to that branch → pop stash → unstage .specwork/
```

**Why force-add .specwork/:** `.specwork/` is gitignored. Without `git add -f`, it would not be included in the stash and the pipeline state would be lost.

---

## `/f-status`

See where you are and what to do next:

```
Branch: feature/MYYES-123
Spec:   ✓ spec.md (2 open / 1 resolved OQs)
Plan:   ✓ plan.md (1 open OQ)
Tree:   clean
Next:   /f-plan (recommended, can skip)
        /f-implement
```

## `/f-help`

Full pipeline diagram with contextual next action highlighted.

## `/f-resync`

Rename artifacts after a branch rename.

```bash
/f-resync                          # sync only (git rename already done)
/f-resync feature/MYYES-124        # atomic: git branch -m + sync
```

---

## `/f-handoff`

Package the current pipeline state for consumption by a different agent (Gemini, Copilot, GPT-4, Codex, Claude):

```bash
/f-handoff
```

Creates `execution-pack.md` and `execution-pack.json` in `.specwork/_handoff/` with:
- Complete spec
- Technical plan
- Rules (global + service-specific)
- Implementation cache
- Known blockers from `escalations.md`

**Gate:** blocks if unresolved Open Questions exist.

---

<!-- _class: divider -->

# 07
## Companion commands

---

## Doc / ADR commands

Beyond the pipeline, open-sdd bundles companion commands:

| Command | What it does |
|---------|--------------|
| **`/doc-catalog`** | Scan current microservice, generate `docs/service-info.md` |
| **`/doc-publish`** | Publish catalog to central registry |
| **`/doc-query`** | Ask cross-service questions across all catalogs |
| **`/doc-adr`** | Create Architecture Decision Record in `docs/adr/` |
| **`/adr-publish`** | Publish ADRs to central registry |
| **`/adr-query`** | Ask decision-history questions across all ADRs |

All loaded automatically by `install.sh`. Registry shared across team via `OPEN_SDD_DOC_HOME`.

---

## Standalone commands

Any branch, any time, no pipeline required:

| Command | When to use |
|---------|-------------|
| `/f-commit` | Semantic commit on any branch |
| `/f-mr` | MR description from git log + push |
| `/f-code-review` | Quality + security on current diff |
| `/f-handoff` | Package spec for another agent |
| `/f-auto` | Full pipeline, one command |

No `.specwork/` required — each detects absence and adapts.

---

<!-- _class: divider -->

# 08
## Requirements and setup

---

## Required tools

| Tool | Version | Why | Windows | macOS | Linux |
|------|---------|-----|---------|-------|-------|
| **LLM agent** (Claude, GPT, Gemini, Copilot, etc.) | Latest | Runs the LLM, interprets `/f-*` commands, drives the pipeline | ✅ Desktop app or terminal via WSL2 | ✅ Terminal or desktop app | ✅ Terminal or desktop app |
| **git** | >= 2.x | All version control operations | ✅ Git Bash or WSL2 | ✅ Built-in or Xcode CLI | ✅ Built-in |
| **Bash** | >= 4.x | All pipeline scripts (`commands/*.sh`) | ✅ Git Bash or WSL2 | ✅ Built-in | ✅ Built-in |
| **Python** | >= 3.9 | Engine layer (`engine/`) | ✅ python.org or WSL2 | ✅ Built-in | ✅ Built-in |

**How to install the LLM agent:**

Install your preferred LLM agent (Claude Code, Copilot, GPT, Gemini, etc.) following its own installation instructions.

---

## Optional tools

| Tool | When you need it | How to install |
|------|-----------------|----------------|
| **GitHub CLI (`gh`)** | Automatic MR creation and merge status checks | `brew install gh` (macOS), `winget install GitHub.cli` (Windows), or [cli.github.com](https://cli.github.com) |
| **GitLab CLI (`glab`)** | Automatic MR creation on self-hosted GitLab | `brew install glab` (macOS) or `winget install glab` (Windows) |
| **Jira credentials** | Automatic ticket fetching in `/f-start` | Set env vars `JIRA_BASE_URL`, `JIRA_USER`, `JIRA_TOKEN` |
| **`jq`** | Jira JSON response parsing (if using Jira) | `brew install jq` (macOS), `apt install jq` (Linux), `winget install jqlang.jq` (Windows) |

---

## Project toolchain (required by `check.sh`)

The quality gate (`check.sh`) auto-detects your project's stack and runs its test command. You need whatever your project needs:

| Detected file | Command run | You need installed |
|---------------|-------------|-------------------|
| `build.gradle` / `build.gradle.kts` | `./gradlew check` | Java + Gradle wrapper (bundled) |
| `pom.xml` | `mvn verify` | Java + Maven |
| `package.json` + `pnpm-lock.yaml` | `pnpm test` | Node.js + pnpm |
| `package.json` + `yarn.lock` | `yarn test` | Node.js + Yarn |
| `package.json` (npm) | `npm test` | Node.js + npm |
| `pyproject.toml` / `setup.py` | `pytest` | Python + dependencies |
| `Cargo.toml` | `cargo test` | Rust + Cargo |
| `go.mod` | `go test ./...` | Go |

---

## Windows setup

The pipeline is built on **bash scripts**. On Windows you have two options:

**Option A — WSL2 (recommended):**
```bash
# 1. Install WSL2 with Ubuntu
wsl --install

# 2. Inside WSL2, install your preferred LLM agent

# 3. Clone open-sdd inside WSL2
git clone <repo-url> ~/team/Yield/open-sdd
./open-sdd/install.sh

# 4. Work from inside WSL2 terminal
```

**Option B — Git Bash:**
1. Install [Git for Windows](https://git-scm.com/download/win) (comes with Git Bash)
2. Install [Python for Windows](https://python.org/downloads/) — check "Add Python to PATH"
3. Clone open-sdd: `git clone <repo-url> ~/team/Yield/open-sdd`
4. Run `install.sh` from **Git Bash** (not CMD or PowerShell)
5. Configure your LLM agent to run commands via Git Bash, or use WSL2 for full compatibility

```bash
# Git Bash (run as Administrator if needed)
cd ~/team/Yield/open-sdd
bash install.sh
```

**Optional tools (Git Bash):** `winget install GitHub.cli` (gh) · `winget install glab` (GitLab CLI, needed by `/f-mr-review`).

> **Important:** Some LLM agent terminals on Windows use PowerShell by default, which does not understand bash-style clickable paths like `/home/user/file:42`. Either use WSL2 (option A) or configure your agent to launch Git Bash as its shell backend.

**Troubleshooting:**

| Symptom | Fix |
|---------|-----|
| `bash: command not found` | You're in CMD/PowerShell. Open Git Bash or the Ubuntu terminal. |
| `python3: command not found` | Install Python and add to PATH (Git Bash) or `sudo apt install python3` (WSL2). |
| `install.sh: syntax error` | Run with CMD/PowerShell instead of bash. Use Git Bash. |
| `glab: command not found` | `winget install glab` (Git Bash) / `sudo apt install glab` (WSL2). Fallback: pass branch names to `/f-mr-review`. |
| Git operations are slow | Cloned on `/mnt/c/`. Re-clone inside Linux filesystem (`~/team/`). |
| agent can't find bash | Point your agent's shell setting to `C:\Program Files\Git\bin\bash.exe` (Git Bash) or use WSL2 terminal. |

---

## macOS setup

```bash
# 1. Install your preferred LLM agent (e.g., Claude Code, GPT, Gemini)

# 2. Clone and install open-sdd
git clone <repo-url> ~/team/Yield/open-sdd
cd ~/team/Yield/open-sdd
bash install.sh

# 3. (Optional) GitHub CLI for automatic MR creation
brew install gh && gh auth login

# 4. (Optional) Jira credentials
echo 'export JIRA_BASE_URL="https://your-company.atlassian.net"' >> ~/.zshrc
echo 'export JIRA_USER="your.email@company.com"' >> ~/.zshrc
echo 'export JIRA_TOKEN="your-atlassian-api-token"' >> ~/.zshrc
```

---

## Linux setup

```bash
# 1. Install your preferred LLM agent (e.g., Claude Code, GPT, Gemini)

# 2. Clone and install open-sdd
git clone <repo-url> ~/team/Yield/open-sdd
cd ~/team/Yield/open-sdd
bash install.sh

# 3. (Optional) GitHub CLI
sudo apt install gh && gh auth login   # Debian/Ubuntu
sudo dnf install gh && gh auth login   # Fedora

# 4. (Optional) Jira credentials — add to ~/.bashrc
```

---

## Per-project initialization

After installing open-sdd globally, initialize each consumer project:

```bash
# Inside the project directory
/f-start MYYES-12345
```

**First run auto-bootstraps:**
- `.opensdd/mr-config.json` — MR target branch and strategy
- `.opensdd/service-rules.md` — service invariants (copy template)
- Appends `.specwork/` to `.gitignore`

---

## Optional configuration

**Jira integration** (fetch tickets automatically):

```bash
export JIRA_BASE_URL="https://your-company.atlassian.net"
export JIRA_USER="your.email@company.com"
export JIRA_TOKEN="your-atlassian-api-token"
```

**MR config** (`.opensdd/mr-config.json`, per project):

```json
{
  "target_branch": "development",
  "merge_strategy": "squash"
}
```

**Service rules** (`.opensdd/service-rules.md`, per project):
Document service invariants, business rules, architecture constraints.

---

<!-- _class: divider -->

# 09
## Comparison with other tools

---

## Landscape

| Tool | Focus | Limitation |
|------|-------|------------|
| GitHub Copilot / Cursor | Code autocomplete | No business context, no pipeline |
| Devin / SWE-agent | Autonomous agent | Black box, hard to audit, expensive |
| Jira + GitLab | Ticket + MR management | No connection between them |
| Conventional Commits | Commit messages only | Very limited scope |
| Claude Code (generic) | General assistant | No structure, no state between sessions |
| **open-sdd** | **Ticket → spec → plan → code → tests → MR** | **Continuous, auditable, local-first, offline** |

**What makes open-sdd different:**
- Local state in `.specwork/`, no server
- Framework-agnostic (Java, Node, Go, Python, Rust)
- LLM-agnostic (works with Ollama, GPT, Claude, Gemini)
- Team-consistent via `install.sh` (everyone runs the same version)
- No vendor lock — pure shell + Python, zero API dependencies

---

## Summary

| Stage | Command | Artifact |
|-------|---------|----------|
| Autopilot | `/f-auto` | Full pipeline non-interactive → MR |
| Entry | `/f-start` | Branch + source.md + state |
| Spec | `/f-spec` | `.specwork/_spec/` |
| Plan | `/f-plan` *(optional)* | `.specwork/_plan/` |
| Implement | `/f-implement` (×N) | Code changes |
| Commit | `/f-commit` | One semantic commit |
| Tests | `/f-test-design` + `/f-test-impl` *(high-risk)* | Test files |
| Review | `/f-code-review` *(optional)* | `.specwork/_review/` |
| MR | `/f-mr` | Published spec + GitLab/GitHub MR |
| Post-review | `/f-mr-address` | Resolved review threads |
| Close | `/f-close` | Clean workspace |

**Autopilot:** `/f-auto <ticket-or-text>` — one command, no prompts, stops at OQs + risk signals, ends at open MR.

**Standalone:** `/f-commit` · `/f-mr` · `/f-code-review` · `/f-handoff`

**Doc commands:** `/doc-adr` · `/doc-catalog` · `/doc-query`

---

<!-- _class: lead -->

# Questions

**Repo:** `team/Yield/open-sdd`

```bash
./install.sh        # register /f-* commands
/f-help             # get your bearings at any point
/f-auto "..."       # run the full pipeline non-interactively
```

> The pipeline is team code.
> If something doesn't work as expected, open an MR.
