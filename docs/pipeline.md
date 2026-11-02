# open-sdd Pipeline — Flow, Commands & Cadence

The full spec-driven flow, the per-command reference, and how to feed it well.
For setup see [setup.md](setup.md); for the gates, artifacts, and stack awareness
it relies on see [concepts.md](concepts.md).

---

## Pipeline Flow

```
  Jira ticket or free-text description
  (start from any branch; create a new branch or continue on current)
          │
          ▼
    ┌─────────────┐
    │  /f-start   │  → pre-flight, create/select branch, write state + source.md (no spec.md yet)
    │  (/f-auto)  │  → non-interactive alternative; runs straight through to the open MR
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
  /f-code-review       — stack-aware quality + security review (your own branch)
  /f-mr-review         — stack-aware peer review of someone else's branch or MR
  /f-undo              — discard uncommitted changes, reversibly (--restore to recover, --hard --force to discard)
                         → see docs/learning/vibe-coding.md

  /f-handoff           — package artifacts for another agent (needs an active pipeline)

UTILITIES:
  /f-help              — where am I, what's next
  /f-status            — detailed pipeline progress
  /f-auto              — run non-interactively through to the open MR
  /f-pause             — stash work without switching branches
  /f-resume            — restore paused work
  /f-undo              — discard a failed/unwanted implementation, keep .specwork/ (reversible; --hard --force to discard permanently)
  /f-resync            — sync artifacts with current branch (`--rename-branch` to rename + sync)
  /f-spec              — draft / refine spec with additional context
                         (canonical spec command)
```

> `/f-auto` runs (`/f-start` or skip if already initialized → `/f-spec` →
> `/f-plan` → `/f-implement` → `/f-commit` → `/f-mr`) **straight through to the
> open MR**. It only pauses for unresolved Open Questions (after `/f-spec`) or,
> when the spec hit a risk area, to ask about the optional test steps (after
> `/f-implement`). It never auto-runs `/f-close` or `/f-mr-address`.
>
> **Open Questions** are unresolved markdown checkboxes (`- [ ]`) in `spec.md`
> (and optionally `plan.md`) that block `/f-implement` until answered.
> `/f-spec` is the canonical way to draft and resolve them. See [concepts.md](concepts.md).

---

## Giving Good Input

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

---

## Pipeline Commands

### /f-auto \<ticket-or-text\>

Non-interactive autopilot for the happy path. Runs `/f-start → /f-spec → /f-plan
→ /f-implement → /f-commit → /f-mr` without bash prompts
(`SDD_NON_INTERACTIVE=1`) and **stops once the MR is open**. No flags: just the
ticket key or free-text description.

It pauses to hand control back to the human in only two cases:

- **Unresolved Open Questions** (after `/f-spec`) — hard stop: asks you to resolve
  them in the spec, then re-run.
- **Risk signals** (after `/f-implement`) — if the spec touched a risk area
  (db-migration, auth, breaking-api, data-destructive, concurrency, …), it stops
  and asks whether to run the optional `/f-test-design` + `/f-test-impl` steps
  (token-costly) before committing. With no risk signals it does **not** stop —
  it runs straight through `/f-commit` and `/f-mr`.

If `check.sh` fails in `/f-mr`, it runs the repair loop without asking (max 3
attempts, guarded and counted by `mr.sh`); still red → it stops without pushing.

It never runs `/f-close` (post-merge) or `/f-mr-address` (requires human review
feedback).

### /f-start \<ticket-or-text\>

- Can start from any branch
- Offers a new working branch based on current HEAD, or stay on current branch
- Writes `.specwork/_state/<slug>-state.json`, `.specwork/_spec/<slug>-source.md`,
  `.specwork/_state/<slug>-rules.json`, `.specwork/_state/<slug>-implementation-cache.json`
- Does **NOT** create `spec.md` — that is `/f-spec`'s job, kept separate
  so each command owns one artifact
- No state machine — each downstream command checks its own artifact preconditions
- Next: `/f-spec`

### /f-spec \<files | jira \<ticket\> | paste | free text\> [--tier \<tier\> "\<reason\>"]

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
- Gives each `## Behavior` item a stable id (`B1`, `B2`, …) and never renumbers
- `--tier <trivial|focused|standard|high-risk|auto> "<reason>"` forces the triage
  tier when the keyword classifier misjudged it (sticky; `auto` drops it)

### /f-plan *(optional)*

- Discovers target files from spec + rules + repo state
- Applies six discovery heuristics: mock-consumer tests, `[infra]`
  exception handlers, test-naming guard, reference-update grep, risk
  surface, and spec-consistency check
- Drafts `.specwork/_plan/<slug>-plan.md` with Target Files, Approach,
  Risks, and Open Questions
- Also writes `.specwork/_plan/<slug>-plan.json` — the machine-readable
  companion (Target Files + per-target progress) that `/f-implement` and
  `/f-mr` consume; absent it, `/f-implement` falls back to inline discovery
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
  - high-risk pipeline with no plan (`/f-spec --tier` can re-tier it)
  - plan.md exists and is stale (newer spec.md)
- Tags each test with the Behavior id(s) it verifies (`// spec: B2`)
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
- **Strict test-coverage gate**; does **not** run `check.sh` (that gates the push)
- Advisory: spec-conformance line (Behaviors with no tagged test) and, on
  high-risk pipelines, the `/f-code-review --auditor` request (once per diff)

### /f-code-review (optional)

- Stack-aware quality and security review of current branch diff
- Checks test coverage (modified classes should have updated tests)
- Detects pack hints (JPA, concurrency, API contracts, logging)
- Writes report to `.specwork/_review/<slug>-code-review.md`
- Supports `--recheck` to compare against previous report

### /f-mr-review \<branch | mr-url | mr-iid\>

- **Peer review** of someone else's committed changes — a branch or a merge request
- Unlike `/f-code-review` (which reviews your own working tree), it resolves a
  *remote* diff via `glab` (MR link/IID) or `git` (branch name) and never touches
  your working tree
- Same review engine as `/f-code-review`: stack-aware quality + security findings
  with `file:line` citations and an advisory test-coverage check
- Writes the report to `.specwork/_review/<slug>-peer-review.md`
- **Read-only**: never checks out, commits, pushes, or comments on the MR

### /f-mr

- **Empty-MR guards**: aborts if on the default branch, or if the branch has no commits beyond its base
- **Host detection**: creates the MR on the *project's own* remote — `gh` for GitHub, `glab` for GitLab. Override with `OPEN_SDD_MR_PROVIDER=github|gitlab` (needed for self-hosted GitLab)
- **Pre-push validation**: runs `commands/check.sh` before every push — the only
  place it runs (after an auto-rebase, the run that followed the rebase counts)
  - Tests fail → does not push; opens a **repair loop**. The agent asks first (`/f-auto` doesn't), fixes the code and re-runs `/f-mr`; `mr.sh` guards and counts each attempt (max 3): no edits to `check.sh` or test configs, no changes to existing tests, no skips. Green → `NOT PUSHED YET` (rc 1): `git add` the listed paths (new files included), `/f-commit`, then `/f-mr`. Still red, declined, or rejected → stops
  - Runs before the `gh`/`glab` checks, so a red build can be repaired without the host CLI set up
- Builds concise MR title and description from spec + commits
- Pushes branch and creates or updates the MR

### /f-handoff (optional)

- Package spec + rules + cache into a model-agnostic execution pack
- Use when handing off to another agent (Gemini, Copilot, Codex, Claude)
- Creates `.specwork/_handoff/<slug>-execution-pack.md` + `.json`
- Gate: no unresolved Open Questions

### /f-mr-address

- Address unresolved MR comments thread by thread
- Tracks progress in `.specwork/_review/<slug>-mr-address.md`

### /f-close [--promote '\<json\>' | --no-promote]

- Refuses when `.specwork/` belongs to another branch
- First pass (interactive, spec present): prints the spec's Safe Constraints and
  resolved Open Questions and stops — nothing deleted — so the agent can propose
  up to 4 durable rules; approved ones are appended to `.claude/rules/*.md` with a
  provenance marker (existing lines are never edited)
- **Reverts uncommitted changes** (`git restore .` + `git clean -fd`), then wipes
  `.specwork/` and `.opensdd/` — run it after the MR is merged
- Offers branch cleanup: delete + switch, keep + switch, or stay

---

## Companion Commands (Doc / ADR)

Beyond the pipeline, open-sdd bundles companion commands for cross-service
documentation and architecture decisions (registered via install.sh):

| Command | What it does |
|---------|--------------|
| **`/doc-catalog`** | Scan the current service and store its catalog in the central registry (`$OPEN_SDD_DOC_HOME/service-catalog/`); `list` shows what is registered |
| **`/doc-catalog-query`** | Ask cross-service architecture questions across all catalogs |
| **`/doc-adr`** | Create an Architecture Decision Record and store it in the registry (`adr-registry/<service>/`); `list` shows them |
| **`/doc-adr-query`** | Ask decision-history questions across all registered ADRs |
| **`/doc-spec`** | Store a hand-written or standalone spec in the registry (`spec-registry/<service>/`) — `/f-mr` does it inside the pipeline |
| **`/doc-spec-query`** | Ask feature/spec questions across the spec registry |
| **`/doc-investigation`** | Capture the current investigation as a structured document (`investigation-registry/<service>/`) |
| **`/doc-investigation-query`** | Ask questions across all captured investigations |
| **`/arch-query`** | Query architecture design documents (`$OPEN_SDD_ARCH_HOME`) |

The `/f-mr` command will suggest running `/doc-adr open-questions` when the
spec has resolved Open Questions worth preserving as ADRs.

**See also:** [docs/learning/doc-adr-cheatsheet.md](learning/doc-adr-cheatsheet.md) — full onboarding & examples

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

To **discard a failed implementation** but keep the pipeline state to re-spec, use
**`/f-undo`** (reversible by default; `--restore` to recover, `--hard --force` to
discard permanently).
See the runbook in [concepts.md](concepts.md#reverting-a-failed-implementation).