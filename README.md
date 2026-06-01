# open-sdd

Open-source Spec-Driven Development pipeline. Framework-agnostic, LLM-agnostic.

A portable reimplementation of the SDD pipeline — decoupled to work with any LLM
(Ollama, GPT, Claude, Gemini) or purely as shell scripts.

> **Just want to code without the full pipeline?** See
> [docs/learning/vibe-coding.md](docs/learning/vibe-coding.md) — the standalone `/f-commit`,
> `/f-mr`, and `/f-code-review` commands work on any branch with no setup.

## Pipeline Flow

```
  Jira ticket or free-text description
  (start from any branch; create a new branch or continue on current)
          │
          ▼
    ┌─────────────┐
    │  /f-start   │  → pre-flight, create/select branch, write state + source.md (no spec.md yet)
    │  (/f-auto)  │  → non-interactive alternative; runs through implement, then pauses pre-commit
    └──────┬──────┘
           ▼
    ┌─────────────┐
    │  /f-spec    │  → draft (first call) or refine (subsequent calls) the spec
    └──────┬──────┘     idempotent; bumps spec_write_timestamp every write
           │  ◄──── re-run any time to add context, resolve Open Questions, expand scope
           ▼              (warns if plan.md is now stale)
    ┌─────────────┐
    │  /f-plan    │  (optional) → discover target files, draft plan, seed cache
    └──────┬──────┘  ◄──── re-run after /f-spec to clear staleness
           │
           ▼
    ┌──────────────────────────────────┐
    │  /f-implement (repeat N times)   │ ◄─── one focused step per run
    │                                  │      reads plan if present (and fresh)
    │   context switch?  → /f-pause    │      gates: unresolved Open Questions · stale plan
    │   resume work?     → /f-resume   │      inline tests as you go
    └──────────┬───────────────────────┘
               │
       complexity assessment
               │
       ┌───────┴──────────┐
  low/medium           high-risk (optional, skippable)
       │                   │
       ▼                   ▼
  /f-commit         /f-test-design  → design test cases (writes artifact)
       │             /f-test-impl   → implement tests (needs test-design)
       │             /f-commit       (or skip the test steps → /f-commit)
       └──────┬──────┘
              │  implementation complete
      ┌────────────────┐
      │ /f-code-review │ (optional)
      └───────┬────────┘
              │
      ┌────────────────┐
      │   /f-mr        │  → push, create MR
      └───────┬────────┘
              │
      ┌───────────────┐
      │ /f-mr-address │  (address review comments)
      └───────┬───────┘
              │  merged
      ┌──────────────┐
      │  /f-close    │  → clean .specwork/
      └──────────────┘

INDEPENDENT — vibe coding (any branch, any time, no pipeline needed):
  /f-commit            — semantic commit messages
  /f-mr                — MR description & creation
  /f-code-review       — stack-aware quality + security review
                         → see docs/learning/vibe-coding.md

  /f-handoff           — package artifacts for another agent (needs an active pipeline)

UTILITIES:
  /f-help              — where am I, what's next
  /f-status            — detailed pipeline progress
  /f-auto              — run non-interactively up to pre-commit handoff
  /f-pause             — stash work without switching branches
  /f-resume            — restore paused work
  /f-resync            — sync artifacts with current branch (`--rename-branch` to rename + sync)
  /f-spec              — draft / refine spec with additional context
                         (canonical spec command)
```

> `/f-auto` runs (`/f-start` or skip if already initialized → `/f-spec` →
> `/f-plan` → `/f-implement`) and then **stops before `/f-commit`** for manual review.
> After that handoff, run `/f-commit`; if it came from `/f-auto`, it auto-runs
> `/f-mr` and then stops. It never auto-runs `/f-close`.
>
> **Open Questions** are unresolved markdown checkboxes (`- [ ]`) in `spec.md`
> (and optionally `plan.md`) that block `/f-implement` until answered.
> `/f-spec` is the canonical way to draft and resolve them.

## Install

open-sdd is **fully self-contained** — everything lives in this repo.

Registers all 28 commands (19 pipeline + 9 doc/adr) as custom commands with tab-completion:

```bash
git clone <repo-url> ~/team/Yield/open-sdd
./open-sdd/install.sh
```

Re-run `install.sh` after moving open-sdd or adding new commands.

### Per-project setup

In each consumer project where you want to use the pipeline:

1. Install open-sdd globally (see Install above)
2. *(Recommended)* Run `/init` inside the project so opencode creates a project-level `AGENTS.md` with build commands, architecture, and conventions.

The first `/f-start` auto-bootstraps `.opensdd/service-rules.md`
and `.opensdd/mr-config.json` in the project.

> **How instructions are loaded.** opencode loads **two separate sources** without conflict:
> - **Global instructions** (`~/.config/opencode/instructions/sdd-pipeline.md`) — installed by `install.sh` with the SDD pipeline rules and command mappings. Referenced from `opencode.json` via the `instructions` field.
> - **Project memory** (`<project>/AGENTS.md`) — created by `/init` with project-specific guidance (build commands, architecture, conventions).
>
> The global file tells the model how to run the pipeline. The project file tells it how your codebase is structured. They complement each other. `/init` never touches the global instructions, and if a project `AGENTS.md` already exists, `/init` improves it in place.
>
> **Note on auto-generation:** Some proactive models (Sonnet, Opus, GPT-4) may auto-create an `AGENTS.md` at startup if none exists. This is the model's behavior, not opencode's. If you prefer to control when and how it's generated, run `/init` manually.

## One-Time Setup

### Jira REST credentials (optional but recommended)

```zsh
export JIRA_BASE_URL="https://your-company.atlassian.net"
export JIRA_USER="your.email@company.com"
export JIRA_TOKEN="your-atlassian-api-token"
```

Without Jira credentials, `/f-start` falls back to free-text input.

### `.specwork/` is gitignored

`.specwork/` is **transient runtime state** — spec drafts, plan, cache, escalation
log — and must never be committed. The permanent artifacts are the commits, the
published spec (`docs/specs/<slug>-spec.md`, if `/f-mr` publishes it), and any
ADRs.

`/f-start` enforces this automatically: on first run in a project it appends
`.specwork/` to `.gitignore` (or creates `.gitignore` if missing). If files were
already tracked from a prior setup, it warns with the exact `git rm --cached`
command to untrack them.

`.opensdd/` (the per-project config directory — `mr-config.json`,
`service-rules.md`) **is** committed.

### MR config

Project config (`.opensdd/mr-config.json`, commit this):

```json
{
  "target_branch": "development",
  "merge_strategy": "squash"
}
```

### Validation script (`commands/check.sh`)

`/f-commit` and `/f-mr` run `bash commands/check.sh` as the quality gate
before committing and pushing. The pipeline treats `exit 0` as clean and
any non-zero exit as a stop signal.

open-sdd ships a **stack-detecting default** at
`$OPEN_SDD_ROOT/commands/check.sh`. It inspects the project root and runs
the standard command for the detected stack:

| Detected file | Command run |
|---|---|
| `build.gradle` / `build.gradle.kts` | `./gradlew check` |
| `pom.xml` | `mvn verify` |
| `package.json` + `pnpm-lock.yaml` | `pnpm test` |
| `package.json` + `yarn.lock` | `yarn test` |
| `package.json` (npm) | `npm test` |
| `Cargo.toml` | `cargo test` |
| `pyproject.toml` / `setup.py` / `setup.cfg` | `pytest` |
| `go.mod` | `go test ./...` |

For most projects this is enough — no setup required.

**Project-local override.** When the framework default is not enough (e.g.
Spring Boot with a separate `integrationTest` source set, Maven with
profiles, monorepos that chain multiple commands, lint/format steps not
wired into the default lifecycle), drop a script at `commands/check.sh` in
the project root and `/f-commit` and `/f-mr` will prefer it over the
framework default. A template ships with open-sdd:

```bash
# from the project root
mkdir -p commands
cp "$OPEN_SDD_ROOT/templates/check.sh.example" commands/check.sh
git add commands/check.sh
git commit -m "chore: add commands/check.sh for project-specific validation"
```

What the override *should* do:

- Run the same commands CI runs (unit + integration + lint + format).
- Exit non-zero on any failure (`set -euo pipefail` at the top handles this).
- Stay reproducible — no network, no cache reliance, no randomness.

What it *should not* do:

- Talk to remote services (Jira, Slack, deploy endpoints).
- Mutate working state (no commits, no `git push`, no schema migrations).
- Run optional/slow workflows that aren't in CI.

**Windows:** the file is bash. Run it through Git Bash or WSL2; the Gradle
/ Maven / npm CLIs invoked inside work identically from those shells.

### Service rules (optional but recommended)

Copy `templates/service-rules.md` to `.opensdd/service-rules.md` and
document service-level invariants: business rules, fallback behavior,
architecture constraints, historical guarantees.

`/f-start` reads both `rules.md` (open-sdd global rules) and
`.opensdd/service-rules.md` (per-project invariants) and compiles them
into `.specwork/_state/<slug>-rules.json`.

### Doc registry (optional)

open-sdd bundles doc commands (`/doc-adr`, `/doc-catalog`, `/doc-publish`,
`/doc-query`, `/adr-publish`, `/adr-query`) that publish and query a
central registry of service catalogs and ADRs. The registry location is
controlled by:

```bash
export OPEN_SDD_DOC_HOME=/path/to/shared/registry
```

Default: `${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry/`.

---

## Pipeline Commands

### /f-auto \<ticket-or-text\>

Non-interactive autopilot for the happy path. Runs `/f-start → /f-spec → /f-plan
→ /f-implement` without bash prompts (`SDD_NON_INTERACTIVE=1`). Then it pauses
before commit so you can review changes. No flags: just the ticket key or
free-text description.

It hands control back to the human at exactly two points:

- **Unresolved Open Questions** (after `/f-spec`): stops and asks you to resolve
  them in the spec, then re-run.
- **Pre-commit review handoff**: after `/f-implement`, it always pauses so you
  can verify diffs before creating a commit.

After your manual `/f-commit`, if the run originated from `/f-auto`, commit
will open/update the MR automatically (`/f-mr`) and stop there. It never runs
`/f-close` (post-merge) or `/f-mr-address` (requires human review feedback).

### /f-start \<ticket-or-text\>

- Can start from any branch
- Offers a new working branch based on current HEAD, or stay on current branch
- Writes `.specwork/_state/<slug>-state.json`, `_spec/<slug>-source.md`,
  `_state/<slug>-rules.json`, `_state/<slug>-implementation-cache.json`
- Does **NOT** create `spec.md` — that is `/f-spec`'s job, kept separate
  so each command owns one artifact
- No state machine — each downstream command checks its own artifact preconditions
- Next: `/f-spec`

#### Giving good input to `/f-start`

The spec is only as good as what you feed the pipeline. `/f-start` doesn't write
the spec — it captures a **source** (`source.md`) that `/f-spec` turns into one.
Both entry points persist that source on disk, so context you provide up front
survives the whole run (including a `/f-auto` run that later stops at a gate):

- **Jira** (`/f-start MYYES-1234`) — the full issue (summary, description, etc.)
  is fetched into `source.md`.
- **Free text** (`/f-start "summary: … behaviour: …"`) — your description is
  written verbatim into `source.md` (via `--source-body-file`). The richer the
  text, the better the first draft; a bare one-liner leans mostly on what can be
  inferred from the codebase.

Because free text is preserved, a **structured block maps straight onto the
spec's canonical sections** — give it to `/f-start` or `/f-auto` and `/f-spec`
drafts from it:

```
/f-auto "summary: dedupe leads when applicationId is null
behaviour: 1) given a null applicationId, skip dedupe instead of throwing
scope: only LeadProcessor; do not touch the SNS publisher
implementation context: LeadProcessor, LeadRepository
safe constraints: idempotent per applicationId; no schema change"
```

### Where deeper context belongs

The `/f-start` source seeds the spec, but two kinds of detail are better added
where the pipeline can act on them:

- **Target classes / files** also land in `## Implementation Context` and
  `## Expected Change Scope` (`Expected files touched`, `Expected layers`,
  `Avoid touching`). You can name them in the source block, but you can also:
  1. Pass files to `/f-spec` directly — `/f-spec src/.../LeadProcessor.java
     src/.../LeadRepository.java` — which also seeds `implementation-cache.json`.
  2. Run `/f-plan`, which discovers targets automatically (mock-consumer tests,
     exception handlers, reference grep). For 3+ file features, prefer discovery
     over hand-listing.
- **Answers to Open Questions** that surface after drafting → feed them back with
  `/f-spec` (a file, a Jira ticket, a paste, or free text). That's the canonical
  way to clear the gate that blocks `/f-implement`.

### What makes a good source (ticket or free-text block)

Aim to give material for each canonical spec section:

| Spec section | What the ticket should provide |
|---|---|
| **Summary** | What and **why** — the problem, not just the task |
| **Behavior** | Acceptance criteria as numbered, observable behaviors ("given X, when Y, then Z") |
| **Scope (in/out)** | Explicit boundaries — what **not** to touch keeps the draft from sprawling |
| **Implementation Context / Expected Change Scope** | Affected services, classes, endpoints if known |
| **Safe Constraints** | Invariants: PII, idempotency, API backward-compat, SLA/retry, DB migration |
| **Open Questions** | Known unknowns — state them; the pipeline turns each into a gate that blocks `/f-implement` until resolved |

A vague ticket ("fix the leads bug") with no expected behavior or boundaries
makes `/f-spec` emit mostly Open Questions and stall the run. Spend the context
up front and the rest of the pipeline flows.

### /f-spec \<files | jira \<ticket\> | paste | free text\>

- Single command for both the first draft and every subsequent refine
- **Draft mode** (`spec.md` does not exist yet): synthesizes the first
  full spec from `source.md` + `templates/spec.md` + any extra context
- **Refine mode** (`spec.md` already exists): integrates new
  context into the existing spec — resolves Open Questions, expands
  `## Implementation Context`, appends to `## Safe Constraints`,
  adjusts `## Expected Change Scope`
- Mixed input: files + Jira ticket + free text in a single call
- **Always bumps `spec_write_timestamp`** so downstream gates see the change
- **Warns** when `plan.md` is older than the new spec or when the working
  tree has uncommitted changes
- Never deletes user content, never touches `source.md` / `rules.json`,
  never modifies git state

### /f-plan *(optional)*

- Discovers target files from spec + rules + repo state
- Applies six discovery heuristics: mock-consumer tests, `[infra]`
  exception handlers, test-naming guard, reference-update grep, risk
  surface, and spec-consistency check
- Drafts `.specwork/_plan/<slug>-plan.md` with Target Files, Approach,
  Risks, and Open Questions
- Seeds `.specwork/_state/<slug>-implementation-cache.json`
- **Gate**: blocks if spec has unresolved Open Questions
- **Staleness**: after `/f-spec` or manual spec edit, the plan goes
  stale (`spec.md` newer than `plan.md`). Re-run `/f-plan` or delete
  `plan.md` to fall back to inline discovery
- **When to use**: medium-to-large features (3+ files), refactors with
  broad blast radius
- **When to skip**: small/obvious changes (1-2 files)
- Next: `/f-implement`

### /f-implement (repeat N times)

- Implement one focused step at a time
- Inline tests validate each step immediately
- Changes accumulate in working tree (no commits between steps)
- **Strict gates** (abort with no writes):
  - Unresolved Open Questions in spec.md or plan.md
  - plan.md exists and is stale (newer spec.md)
- Complexity assessment at the end:
  - Low/isolated → `/f-commit`
  - High/multi-layer → `/f-test-design`

### /f-test-design (optional — high-risk flow)

- Analyzes the diff, designs test cases, and writes `.specwork/_test/<slug>-test-design.md`
- Runs **inside an active pipeline** (after `/f-implement`) — not a standalone tool
- Tracked only in the `high-risk` flow; **skippable** — go straight to `/f-commit`

### /f-test-impl (optional — high-risk flow)

- Implements the test files following the cases from the test-design artifact
- **Depends on `/f-test-design`**: reads `.specwork/_test/<slug>-test-design.md` and aborts if it is missing
- Runs **inside an active pipeline**; **skippable** — go straight to `/f-commit`

### /f-commit (one commit at the end)

- Creates a single commit for all accumulated changes
- Auto-stages modified/new files when nothing is staged
- Generates a semantic commit message from spec title + optional ticket ref
- User approves before commit

### /f-code-review (optional)

- Stack-aware quality and security review of current branch diff
- Checks test coverage (modified classes should have updated tests)
- Detects pack hints (JPA, concurrency, API contracts, logging)
- Writes report to `.specwork/_review/<slug>-code-review.md`
- Supports `--recheck` to compare against previous report

### /f-mr

- **Empty-MR guards**: aborts if on the default branch, or if the branch has no commits beyond its base
- **Host detection**: creates the MR on the *project's own* remote — `gh` for GitHub, `glab` for GitLab. Override with `OPEN_SDD_MR_PROVIDER=github|gitlab` (needed for self-hosted GitLab)
- **Pre-push validation**: runs the test suite before push, but **skips it when HEAD was already validated by `/f-commit`**
  - Tests fail → stops, does not push
- Builds concise MR title and description from spec + commits
- Pushes branch and creates or updates the MR
- Optional: `--skip-validation` for emergencies

### /f-handoff (optional)

- Package spec + rules + cache into a model-agnostic execution pack
- Use when handing off to another agent (Gemini, Copilot, Codex, Claude)
- Creates `.specwork/_handoff/<slug>-execution-pack.md` + `.json`
- Gate: no unresolved Open Questions

### /f-mr-address

- Address unresolved MR comments thread by thread
- Tracks progress in `.specwork/_review/<slug>-mr-address.md`

### /f-close

- Wipes `.specwork/` after merge
- Verifies MR merge status via `gh`
- Never reverts or deletes source-tree changes outside `.specwork/`

---

## Companion Commands (Doc / ADR)

Beyond the pipeline, open-sdd bundles companion commands for cross-service
documentation and architecture decisions (registered via install.sh):

| Command | What it does |
|---------|--------------|
| **`/doc-catalog`** | Scan the current microservice and generate `docs/service-info.md` with endpoints, integrations, and config |
| **`/doc-publish`** | Publish the catalog to the central registry (`$OPEN_SDD_DOC_HOME/service-catalog/`). `--with-docs` also publishes `docs/architecture/`, `docs/product/`, `docs/security/`, `docs/features/` |
| **`/doc-query`** | Ask cross-service questions across all registered documents (catalogs + extra docs) |
| **`/doc-freshness`** | Detect drift between docs and repo: broken links, orphan files, version mismatch, stale dates, missing endpoints |
| **`/spec-query`** | Query product specs (product-spec.md, gap-analysis.md, feature-inventory.md) from the registry |
| **`/sec-query`** | Query security docs (security-report.md, gl-\*-report\*.json) from the registry |
| **`/doc-adr`** | Create an Architecture Decision Record in `docs/adr/` |
| **`/adr-publish`** | Publish all ADRs to the central registry (`$OPEN_SDD_DOC_HOME/adr-registry/<service>/`) |
| **`/adr-query`** | Ask decision-history questions across all registered ADRs |

The `/f-mr` command will suggest running `/doc-adr open-questions` when the
spec has resolved Open Questions worth preserving as ADRs.

**See also:** [docs/learning/doc-adr-cheatsheet.md](docs/learning/doc-adr-cheatsheet.md) — full onboarding & examples

---

## Implementation Cadence

```bash
/f-implement    # code + inline tests — low complexity
/f-implement    # code + inline tests — low complexity
/f-implement    # code + inline tests — HIGH → recommends /f-test-design

/f-test-design  # (high-risk, optional) design test cases → writes artifact
/f-test-impl    # (high-risk, optional) implement them — requires test-design first

/f-commit       # one commit for all accumulated changes

/f-mr           # validates tests (skips if already validated), pushes, creates MR
```

> `/f-test-design` and `/f-test-impl` are optional steps tracked only in the
> `high-risk` flow. `/f-test-impl` depends on `/f-test-design`'s artifact — run
> them in order, or skip both straight to `/f-commit`.

**Advantages:**
- Fast iteration: run `/f-implement` N times without commit overhead
- Immediate feedback: each step validates its own tests
- Clean history: one logical commit per coherent set of changes
- Single validation gate: tests validated once in `/f-mr` before push

---

## Context Switching

```
/f-pause  → stash work (including .specwork/) without switching branches
/f-resume → switch back to the recorded branch and restore paused feature work
```

---

## Artifacts

Transient (`.specwork/`, gitignored):

| Path | Description |
|------|-------------|
| `_state/<slug>-state.json` | Branch metadata (branch, slug, ticket, timestamps) |
| `_state/<slug>-rules.json` | Compiled global + service rules |
| `_state/<slug>-implementation-cache.json` | Implementation memory (repositories, patterns, tests) |
| `_spec/<slug>-spec.md` | Implementation specification |
| `_spec/<slug>-source.md` | Raw input from Jira (or free text) |
| `_plan/<slug>-plan.md` | Target files, approach, risks |
| `_plan/<slug>-plan.json` | Plan metadata (progress, staleness check) |
| `_test/<slug>-test-design.md` | Designed test cases from `/f-test-design`; consumed by `/f-test-impl` (high-risk flow) |
| `_progress/escalations.md` | Append-only log of implementation escalations |
| `_review/<slug>-code-review.md` | Code review report (optional) |
| `_review/<slug>-mr-address.md` | Review comment resolution progress |
| `_handoff/<slug>-execution-pack.md` | Handoff contract (optional) |
| `_handoff/<slug>-execution-pack.json` | Handoff metadata (optional) |

### _progress/ — Execution Memory

`_progress/` is mutable runtime memory. It captures what happened during
execution: blockers, decisions, hints.

- `escalations.md` — `/f-implement` appends a dated entry whenever its
  escalation policy triggers (test loops, infrastructure failures,
  persistent retries). `/f-handoff` reads it and surfaces a
  *Known Blockers* section in the execution capsule.

### Per-project config (committed)

| Path | Description |
|------|-------------|
| `.opensdd/service-rules.md` | Service-level invariants |
| `.opensdd/mr-config.json` | MR target branch, merge strategy |

---

## Structure

```
open-sdd/
├── agent/
│   └── PIPELINE.md   # System prompt for any LLM
├── lib/
│   ├── gates.sh                     # Validation gates
│   └── jira.sh                      # Jira REST client via curl
├── commands/                        # 31 scripts (28 user-facing commands + internal helpers)
│   ├── check.sh
│   ├── code-review.sh
│   ├── commit.sh
│   ├── handoff.sh
│   ├── help.sh
│   ├── implement.sh
│   ├── mr-address.sh
│   ├── mr.sh
│   ├── pause.sh
│   ├── plan.sh
│   ├── resume.sh
│   ├── resync.sh
│   ├── spec.sh                      # Draft / refine spec
│   ├── start.sh
│   ├── status.sh
│   ├── test-design.sh
│   ├── test-impl.sh
│   ├── doc-catalog.sh               # doc/adr commands (9)
│   ├── doc-publish.sh
│   ├── doc-query.sh
│   ├── doc-freshness.sh
│   ├── doc-adr.sh
│   ├── spec-query.sh
│   ├── sec-query.sh
│   ├── adr-publish.sh
│   └── adr-query.sh
├── templates/
│   ├── rules.md                     # Global pipeline rules (compiled at /f-start)
│   ├── service-rules.md             # Per-project invariants (copy to .opensdd/)
│   ├── rules.json                   # Rules schema template
│   ├── spec.md                      # Spec scaffold template
│   └── mr-config.json               # MR config template
└── install.sh                       # Register /f-* commands as custom commands
```

---

## Bugs fixed from the original

| Bug | Fix |
|-----|-----|
| mtime gate false negative after git stash (f-pause destroys mtime) | `spec_write_timestamp` stored in `state.json`, not filesystem mtime |
| Java-only heuristics silently skip Node/TS projects | Stack detection (`build.gradle`/`pom.xml` → java, `package.json` + frontend config → frontend, `package.json` only → node) with per-stack heuristics |
| `resolve_slug()` ignored free-text slug in favor of branch name | Matches current branch against `state.json::branch` field first |

---

## UI / Frontend Support

open-sdd detects frontend projects (React, Vue, Angular, Svelte, etc.) and
adapts its heuristics. Stack detection classifies a project as:

| Detection signal | Stack | What changes |
|-----------------|-------|-------------|
| `build.gradle` / `pom.xml` | `java` | Backend JVM heuristics |
| `package.json` + Vite / Next / Angular / Svelte / Nuxt config | `frontend` | Component/page/store discovery + frontend risk signals |
| `package.json` (no frontend config) | `node` | Node backend heuristics (Express/NestJS) |
| None of the above | `unknown` | Spec-body heuristics only |

### Plan heuristics (frontend)

- **Infrastructure discovery**: searches for React error boundaries (`ErrorBoundary`, `componentDidCatch`) and Vue error handlers (`Vue.config.errorHandler`)
- **Mock consumer discovery**: searches for `*Component.tsx`, `*Page.tsx`, `*Hook.ts`, `*Store.ts` patterns alongside the existing `*Service.ts` / `*Client.ts`
- **Test resolution**: resolves `*.test.ts`, `*.test.tsx`, `*.spec.ts`, `*.spec.tsx` in `__tests__/` or sibling directories
- **Reference update**: greps `.ts`, `.tsx`, `.js`, `.jsx`, `.json` files for renamed/removed symbols

### Triage (frontend)

Frontend risk keywords: `state management`, `routing`, `accessibility`/`a11y`,
`ssr`/`hydration`, `data fetching`, `useSWR`/`react-query`, `component migration`,
`i18n`, `theming`, `dark mode`.

Frontend known layers: `component`, `page`, `store`, `hook`, `screen`, `layout`,
`util` — in addition to the standard backend layers.

### Risk signals

Frontend-specific hard keyword matches:

| Signal | Example triggers |
|--------|-----------------|
| `component-api` | props interface change, prop rename/removal, render signature change |
| `state-management` | redux/zustand/context migration, store refactor |
| `accessibility` | a11y, ARIA, keyboard nav, focus trap, WCAG |
| `routing` | react-router, useRouter, navigate, route restructure |
| `data-fetching` | tanstack query, useSWR, Apollo, SSR/hydration |
| `ui-migration` | design system update, UI library upgrade, theming overhaul |

### Test implementation

The HARD RULES table in `/f-test-impl` shows both Java (AssertJ/Mockito) and
frontend (Jest/Vitest/RTL) assertion examples side by side. FORBIDDEN patterns
are shown for both stacks.

### Code review

Frontend diff gets targeted pack hints:
- **Lifecycle hooks**: cleanup and dependency arrays
- **State management**: immutability and re-render scope
- **Memoization**: dependency correctness
- **Accessibility**: ARIA patterns and keyboard navigation
- **Routing**: side effects, guards, error states
- **Dynamic imports**: loading states, bundle splitting

### Spec template

The spec template ships with optional frontend sections. Delete the ones that
don't apply for backend-only features:

```
## UI / Component Breakdown
## User Flows
## Visual / Design Requirements
## Accessibility Requirements
## State Management
## API Contract (Frontend Perspective)
```

---

## Requirements

### Required

| Tool | Version | Why | Windows | macOS | Linux |
|------|---------|-----|---------|-------|-------|
| **LLM client** | Latest | Interprets `/f-*` commands, runs LLM inference | Varies by client | Varies by client | Varies by client |
| **git** | >= 2.x | All version control | Git Bash or WSL2 | Built-in | Built-in |
| **Bash** | >= 4.x | All pipeline scripts (`commands/*.sh`) | Git Bash or WSL2 | Built-in | Built-in |
| **Python** | >= 3.9 | Engine layer (`engine/`) | python.org or WSL2 | Built-in | Built-in |

**Install an LLM client:**

The pipeline commands require an LLM client that supports custom slash commands.
Choose your preferred client and follow its installation instructions.

### Optional

| Tool | When you need it | Install (macOS) | Install (Windows) |
|------|-----------------|-----------------|-------------------|
| **GitHub CLI (`gh`)** | Auto MR creation + merge checks | `brew install gh` | `winget install GitHub.cli` |
| **GitLab CLI (`glab`)** | Auto MR on self-hosted GitLab | `brew install glab` | `winget install glab` |
| **jq** | Jira JSON parsing | `brew install jq` | `winget install jqlang.jq` |

### Project toolchain (required by `check.sh`)

The quality gate auto-detects your project stack and runs its test command:

| Detected file | Command run | You need |
|---------------|-------------|----------|
| `build.gradle` / `build.gradle.kts` | `./gradlew check` | Java (Gradle wrapper is bundled) |
| `pom.xml` | `mvn verify` | Java + Maven |
| `package.json` + `pnpm-lock.yaml` | `pnpm test` | Node.js + pnpm |
| `package.json` + `yarn.lock` | `yarn test` | Node.js + Yarn |
| `package.json` (npm) | `npm test` | Node.js + npm |
| `pyproject.toml` / `setup.py` | `pytest` | Python + deps |
| `Cargo.toml` | `cargo test` | Rust + Cargo |
| `go.mod` | `go test ./...` | Go |

### Jira (optional)

```bash
export JIRA_BASE_URL="https://your-company.atlassian.net"
export JIRA_USER="your.email@company.com"
export JIRA_TOKEN="your-atlassian-api-token"
```

### Windows

The pipeline runs on bash scripts. Two options:

**Option A — WSL2 (recommended):**

Full Linux environment inside Windows. Everything works natively.

```powershell
# 1. Install WSL2 with Ubuntu (run in PowerShell as Admin)
wsl --install

# 2. Restart your machine, then open the "Ubuntu" terminal

# 3. Inside Ubuntu, update packages
sudo apt update && sudo apt upgrade -y

# 4. Clone open-sdd
git clone <repo-url> ~/team/Yield/open-sdd

# 5. Run installer
cd ~/team/Yield/open-sdd && bash install.sh
```

After install, always work from inside the Ubuntu terminal (open via Start menu
or `wsl -d Ubuntu -e bash` from PowerShell). The pipeline, git, and your LLM client all
run inside WSL2.

**Optional tools inside WSL2:**

```bash
# GitHub CLI — auto MR creation
sudo apt install gh

# GitLab CLI — auto MR on self-hosted GitLab
sudo apt install glab    # or: brew install glab (if Homebrew on Linux is set up)
```

> **WSL2 + Windows drives:** Access your Windows files at `/mnt/c/`. Clone repos
> into the Linux filesystem (`~/team/...`) for best performance — `/mnt/c/`
> is noticeably slower for git operations.

---

**Option B — Git Bash:**

Runs bash scripts without WSL2. Some commands (e.g. `glab mr diff`) may need
adjustments.

```powershell
# 1. Install Git for Windows (comes with Git Bash)
#    Download from https://git-scm.com/download/win

# 2. Install Python 3.9+
#    Download from https://python.org/downloads/
#    Check "Add Python to PATH" during install

# 3. Install an LLM client (choose one that supports custom slash commands)

# 4. Clone open-sdd
#    Open Git Bash (Start menu → Git Bash)
git clone <repo-url> ~/team/Yield/open-sdd

# 5. Run installer from Git Bash (not CMD, not PowerShell)
cd ~/team/Yield/open-sdd
bash install.sh
```

**Important:** Some LLM clients default to PowerShell on Windows. When a
command prints a clickable path like `/home/user/repo/file:42`, PowerShell won't
recognise it. Either:
- Use WSL2 (option A) for full compatibility, or
- Configure your LLM client to launch Git Bash as its shell backend

**Optional tools (Git Bash):**

```powershell
# GitHub CLI — auto MR creation
winget install GitHub.cli

# GitLab CLI — auto MR on self-hosted GitLab (needed by /f-mr-review MR mode)
winget install glab
```

---

**Verify installation (both options):**

```bash
# Inside bash (WSL2 or Git Bash), run these checks:
git --version          # should show >= 2.x
bash --version         # should show >= 4.x
python3 --version      # should show >= 3.9
gh --version           # optional, for /f-mr on GitHub
glab version           # optional, for /f-mr on GitLab + /f-mr-review MR mode
```

**Troubleshooting:**

| Symptom | Fix |
|---------|-----|
| `bash: command not found` | You're in CMD or PowerShell. Open Git Bash or the Ubuntu terminal. |
| `python3: command not found` | Install Python and add it to PATH (Git Bash) or `sudo apt install python3` (WSL2). |
| `install.sh: line X: syntax error` | You're running with CMD/PowerShell. Use `bash install.sh` from **Git Bash** or the Ubuntu terminal. |
| `glab: command not found` | `winget install glab` (Git Bash) or `sudo apt install glab` (WSL2). Fallback: pass branch names to `/f-mr-review` instead of MR links. |
| Git operations are slow | You cloned on `/mnt/c/` (Windows drive). Re-clone inside the Linux filesystem (`~/team/`). |
| LLM client can't find bash | Point your client's shell setting to the full path of `bash.exe` (Git Bash: `C:\Program Files\Git\bin\bash.exe`) or use the WSL2 terminal. |

---

## License

MIT
