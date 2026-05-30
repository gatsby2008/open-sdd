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
  table { width: 100%; font-size: 0.9em; }
  th { background: #1C1C1C; color: white; }
  .columns { display: grid; grid-template-columns: 1fr 1fr; gap: 2em; }
  section.lead { background: #1C1C1C; color: white; }
  section.lead h1 { color: #F5A623; border-color: #F5A623; }
  section.lead h2 { color: #E8C97A; }
  section.lead p { color: #ccc; }
  section.divider { background: #2B2B2B; color: white; display: flex; align-items: center; }
  section.divider h1 { color: #F5A623; border: none; font-size: 2.5em; }
  section.divider p { color: #aaa; font-size: 1.2em; }
---

<!-- _class: lead -->

# Spec-Driven Development

## From Jira ticket to merged MR — with context, without guessing

**Yield Team · 2026**

---

## The problem we all know

How does a feature start today?

```
Jira ticket   →   "I know what needs to be done"   →   code   →   surprise review
```

**What it costs us:**
- Requirements clarified after implementation is done
- Unstructured commits ("fix", "wip", "stuff")
- Empty MR descriptions copied from the last commit
- Tests written at the end, or not written at all
- Context-switching that wipes the mental model of the feature

**Question:** how much work does the team do twice today?

---

<!-- _class: divider -->

# 01
## What is Spec-Driven Development?

---

## SDD in one sentence

> The spec is the contract. The implementation executes it — it doesn't invent it.

**The cycle:**

```
Spec → Plan → Implement → Test → Review → MR → permanent docs
```

**How it differs from other approaches:**

| Approach | Where the "what" lives |
|----------|----------------------|
| TDD | In tests (`assert expected == actual`) |
| BDD | In tests (`Given / When / Then`) |
| **SDD** | In a natural language design artifact — *before* touching code |

**Key principle:** the person who specifies and the person who implements are the same — just at different moments in time. The spec is the conversation with your future self.

---

## SDD is not bureaucracy

The spec is not a formal 20-page document.

It's a **structured answer to questions you have to answer anyway:**

- What exactly does this feature do?
- What's out of scope?
- Which endpoint / component / service changes?
- What are the acceptance criteria?
- What don't I know yet? (**Open Questions**)

Open Questions are the real value: forcing the questions *before* implementing
prevents rework when the answers arrive *during* implementation.

---

<!-- _class: divider -->

# 02
## Existing tools today

---

## The current landscape

| Tool | Focus | Limitation |
|------|-------|------------|
| GitHub Copilot / Cursor | Code autocomplete | No business context, no pipeline |
| Devin / SWE-agent | Autonomous full-stack agent | Black box, hard to audit, expensive |
| Linear / Jira + GitLab | Ticket and MR management | Doesn't connect ticket to implementation |
| Conventional Commits tools | Commit messages only | Very limited scope |
| Claude Code standalone | General assistant | No structure, no state between sessions |

**The gap:** no tool connects ticket → spec → plan → code → tests → MR
as a **continuous, auditable flow that works offline**.

---

<!-- _class: divider -->

# 03
## Our pipeline

---

## Why we built it on Claude Code + Skills

**Skills = structured prompts, versioned in git, distributed to the team**

- Each skill has a bounded scope → easy to fix, extend, or replace
- Local state in `.specwork/` → persistent context between sessions, no server
- No additional infrastructure cost
- Every developer uses the exact same version (symlinks from this repo)
- Contributions via MR, just like production code

---

## The full flow

```
                 Interactive:  /f-start  (step by step)
 Entry ───┤
                 Non-interactive: /f-auto  (runs full pipeline — new!)
                                    │
                                    ▼
 /f-spec                           draft structured spec · Open Questions
       ↓
 /f-plan                           step-by-step technical plan
       ↓
 /f-implement  →  /f-commit        code + semantic commit  (repeat per step)
       ↓
 /f-test-design                    test design (gaps only)
 /f-test-impl                      test implementation
       ↓
 /f-spec-review                    spec vs code  →  PASS / FAIL
 /f-code-review                    quality + security review
       ↓
 /f-mr                             MR description + squash + push
       ↓
 /f-review-address                 address review comments thread by thread
       ↓
 /f-close                          artifact cleanup
```

---

## New: `/f-auto` — Non-interactive autopilot

**Single command** that runs the entire pipeline without bash prompts:

```bash
/f-auto MYYES-15535
/f-auto "retry logic for webhooks"
```

**What it does:**
1. Creates branch + writes source.md (like `/f-start`)
2. Drafts the spec (like `/f-spec`)
3. Detects **blocking Open Questions** → stops and alerts
4. Writes the technical plan (like `/f-plan`)
5. Runs `/f-implement` → displays spec + plan + target files
6. Hands off to the LLM for implementation

**It stops for human input at exactly two points:**
- **Unresolved Open Questions** (after `/f-spec`)
- **Concrete risk signal** (before commit) — DB migration, auth/security, data-destructive, concurrency, or breaking API change

**It ends at the open merge request.** It never runs `/f-close` (post-merge, deletes your branch) or `/f-mr-address` (needs review comments that don't exist yet).

---

## Step 1 — Entry: `/f-start` or `/f-auto`

**`/f-start`** — interactive, step-by-step control:

```bash
/f-start MYYES-15535            # automatic fetch from Jira via MCP
/f-start "retry logic webhooks" # free text if no ticket
```

Asks about branch name, writes source.md, then hands off to `/f-spec`.

**`/f-auto`** — non-interactive, runs full pipeline through to open MR:
- No bash prompts (branch creation, commit message, branch deletion)
- Only stops for Open Questions and risk signals
- End state: MR is open, branch is live, pipeline stops

**Both produce the same artifacts in `.specwork/`.**

---

## Step 2 — `/f-spec` (spec)

**Input:** Jira ticket or plain text description
**Output:** structured spec in `.specwork/_spec/`

```bash
/f-spec MYYES-15535            # refine an existing spec with more context
/f-spec "add email templates"  # add context to a draft
```

**The spec includes:**
- Summary, Scope (in/out), Endpoint/Component, Behavior
- Required Changes, New Configuration, Non-Functional Requirements
- Acceptance Criteria
- **Open Questions** — unresolved questions that block the next step

> Review the spec before continuing. Every unresolved Open Question
> is a rework risk.

---

## Step 3 — `/f-plan`

**Input:** spec
**Output:** step-by-step technical plan in `.specwork/_plan/`

- Detects stack automatically (`pom.xml` / `build.gradle` → Java Spring Boot, `package.json` → React/Next.js/Vue)
- Each step is **independently committable** — one class, one component, one migration
- Steps are numbered and tracked in `.specwork/_progress/`
- High-risk steps are marked `⚠ HIGH RISK` — DB migrations, auth changes, cross-service contracts

**Example output:**
```
Step 1/7  Add Flyway migration V23_add_consent_flag
Step 2/7  Implement ConsentRepository method
Step 3/7  Implement ConsentService.saveConsent()
Step 4/7  Add ConsentController POST /api/v1/consent
...
```

---

## Step 4 — `/f-implement` + `/f-commit`

**Two modes:**

**Step by step** — full control, one commit per step:
```bash
/f-implement     # implements step N, offers inline unit tests
/f-commit        # proposes semantic message, marks step as done
```

**All at once** — confirms once, implements and commits automatically:
```bash
/f-implement all
```

**Context utilities:**
```bash
/f-pause    # stashes everything (including .specwork/) back to development
/f-resume   # lists paused features with progress, restores the selected one
/f-status   # where am I and what's next
```

---

## Step 5 — Tests

**`/f-test-design`** — designs *only the gaps*:
- Scans tests already written inline during `/f-implement`
- Identifies: missing integration tests, uncovered edge cases, untested components
- Never duplicates what already exists

**`/f-test-impl`** — implements the designed tests:

| Stack | What it generates |
|-------|------------------|
| Java | `*IntTest.java` / `*IT.java` — detected from project layout (`src/intTest/`) — `@WebMvcTest`, `@DataJpaTest` |
| Frontend | `*.test.tsx` — RTL + MSW, full component tree |

`/f-test-design` guarantees at least one integration test per exposed endpoint.

Both steps are **optional** — the pipeline does not block if they are skipped.

---

## Step 6 — Internal review

**`/f-spec-review`** — validates implementation vs spec:
- Verifies every acceptance criterion is covered
- Detects deviations and unresolved assumptions
- Produces verdict: **PASS / PASS WITH WARNINGS / FAIL**
- A FAIL blocks `/f-code-review` until fixed

**`/f-code-review`** — quality + security:
- Detects stack and launches the corresponding agents in parallel
- Java: `java-quality-reviewer` + `java-security-reviewer`
- Frontend: `ui-quality-reviewer` + `ui-a11y-reviewer`
- Produces findings with severity: **Blocker / Major / Minor**

---

## Step 7 — `/f-mr`

**Automatic pre-flight before generating the MR:**
- **Branch sync:** if the target has new commits, offers rebase — if clean rebase, runs `./gradlew test`
- **Test Design Gate:** warns if `/f-test-design` was skipped and no tests appear in the diff → confirm or cancel
- **Test Coverage Check:** detects modified/new classes with no corresponding tests → lists the gaps

**Generates the MR description from artifacts, then asks how to publish:**

```
Branch:      feature/MYYES-15535 → development
Strategy:    squash — 7 commits → 1
Title:       [MYYES-15535] feat: User Consent Email Integration
Reviewers:   teammate1, teammate2

[s] Publish via glab (ready)
[d] Publish via glab (draft)
[m] Show me the text to paste into GitLab manually
[e] Edit title/description
[x] Cancel
```

**`glab` is optional** — without it, prints title, description, pre-filled URL, and reviewers list for copy-paste. The pipeline never blocks due to missing `glab`.

---

## Step 8 — Closing out

**`/f-review-address`** — when review comments arrive:
- Shows each thread with file + line context
- For each: **fix** (implement + stage + resolve) / **reply** / **defer** / **skip**
- Saves progress, re-running picks up where it left off

**`/f-close`** — after the merge:
- Warns if spec was never published to `docs/specs/`
- Lists everything it will delete, asks for confirmation
- Cleans up `.specwork/` for the next feature

---

## Artifacts: what gets generated and where it lives

<div class="columns">

**Transient** (local, gitignored)
```
.specwork/
  _spec/      ← the contract
  _plan/      ← technical design
  _progress/  ← step tracking
  _test/      ← test design
  _review/    ← review verdicts
  _ticket/    ← Jira dump
```

**Permanent** (committed)
```
docs/
  specs/      ← spec copied by /f-mr
  adr/        ← architecture decisions
```

</div>

**Principle:** transient artifacts guide the work. Permanent artifacts document the decisions.

---

<!-- _class: divider -->

# 04
## Hotfix and Bug Fixing

---

## Full pipeline or short path?

The SDD pipeline is optimized for **new features**. For bugs and hotfixes,
the decision depends on complexity:

| Type | Criteria | Path |
|------|----------|------|
| **Hotfix** | Urgent, focused change, known root cause | Short path |
| **Simple bug** | 1–3 files, clear cause | Short path |
| **Complex bug** | Unknown root cause, multiple services affected, regression risk | Full pipeline |

---

## Short path — Hotfix / Simple bug

```
/f-hotfix MYYES-XXXXX     ← creates hotfix/ from main, writes brief
        ↓
  [ implement the fix ]
        ↓
  /f-commit             ← semantic commit
        ↓
  /f-mr                 ← pre-flight: sync + test coverage
                           MR from git log + brief
        ↓
  /f-close              ← clean up .specwork/
```

**No spec, no plan. The brief lives in `.specwork/_ticket/`.**
All commands work standalone on any branch.

---

## Short path — practical notes

**`/f-hotfix` starts the short path:**
- Verifies you're on `main`, clean tree, and `.specwork/` is empty
- Runs `git fetch` and creates `hotfix/MYYES-XXXXX` from `main`
- Fetches the Jira ticket (if MCP is available) and writes the brief

**`/f-commit` on a hotfix:**
```
[MYYES-XXXXX] fix: prevent NPE when consent flag is null
```
Extracts the ticket from the branch name automatically.

**`/f-mr` on a hotfix:**
- Pre-flight: branch sync + test coverage check
- Generates **What / Why / How / Changes** from `git log` + brief
- If you have `glab`: creates the MR directly; otherwise, copy-paste ready

---

## When to escalate to the full pipeline

A "simple" bug may need the pipeline if:

- The root cause requires changes across **more than one service**
- The fix involves a **database migration**
- There are **Open Questions** about correct behavior (product ambiguity)
- The bug revealed a **design gap** beyond the symptom

In that case, treat it as a feature:
```
/f-spec "fix: bug description and root cause"
```
Then follow the normal pipeline from there.

---

<!-- _class: divider -->

# 05
## Commands independent of the pipeline

---

## Useful in any project, at any time

**Fully independent** — no `.specwork/`, no `feature/*`, no prior `/f-spec`:

| Command / Agent | When to use |
|-----------------|-------------|
| `/java-review` | Quality + security review on staged+unstaged, before committing, on any branch |
| `/doc-adr` | Capture a permanent architecture decision |
| `/doc-catalog` | Generate / update the current microservice catalog |

**Pipeline skills with standalone mode** — part of the pipeline but work alone:

| Skill | Behavior outside the pipeline |
|-------|------------------------------|
| `/f-commit` | Semantic commit on any branch — skips tracking if no `.specwork/` |
| `/f-mr` | Generates MR description from `git log` if no artifacts — prints copy-paste without `glab` |
| `/f-spec` | Creates spec from free text or Jira on any repo — no prior pipeline required |

---

## `/java-review` — pre-commit review

Runs `java-quality-reviewer` + `java-security-reviewer` in parallel on the current diff (staged + unstaged).

**Use cases:**
- **Hotfix** — quick fix outside the pipeline, want a check before committing
- **Mid-implementation** — during `/f-implement`, feedback on the current step before `/f-commit`
- **Config / infra** — changes to `application.yml`, scripts, or migrations outside a formal feature branch

**Key difference from `/f-code-review`:**

| | `/java-review` | `/f-code-review` |
|--|----------------|-----------------|
| Diff scope | staged + unstaged | full branch vs base |
| When to run | before committing | after all commits are ready |
| Pipeline required | no | yes (reads `.specwork/` artifacts) |

---

## `/doc-adr` — Architecture Decision Records

**When:** technology choice, adopted pattern, compliance constraint, significant technical trade-off.

```bash
/doc-adr "use Redis for session cache instead of database"
```

**Generates:** `docs/adr/ADR-0001-redis-session-cache.md` with standard structure:
- Status, Context, Decision, Consequences, Alternatives Considered

**Why it matters:** technical decisions are made once but justified many times.
An ADR prevents the team from re-litigating decisions that are already made and documented.

---

## `/doc-catalog` — Service catalog

**When:** onboarding a new service, or onboarding a new developer.

```bash
/doc-catalog
```

**Generates:** a document with:
- Service responsibility, stack, exposed endpoints
- Upstream/downstream dependencies
- Relevant configuration keys
- Basic runbook

Committed to the repo → always up to date, always accessible.

---

<!-- _class: divider -->

# 06
## UI / Frontend Support

---

## What already works today for frontend

The pipeline detects the stack automatically and adapts its output:

| Skill | Behavior when `package.json` is detected |
|-------|------------------------------------------|
| `/f-plan` | Atomic steps per component / hook / page |
| `/f-test-design` | Designs RTL + MSW tests, covers component tree |
| `/f-test-impl` | Generates `*.test.tsx` with RTL + MSW mocks |
| `/f-code-review` | Launches `ui-quality-reviewer` + `ui-a11y-reviewer` in parallel |

**`ui-quality-reviewer`** reviews: TypeScript strict, unnecessary re-renders, async error handling, naming, duplication — with Next.js + Tailwind + CSS Modules context.

**`ui-a11y-reviewer`** reviews: WCAG 2.1/2.2, ARIA, keyboard navigation, focus management, live region announcements.

---

## Improvement proposals for UI

**What the spec doesn't capture well today (and should):**

The current spec template is oriented toward REST endpoints. For UI features we need different sections:

```markdown
## Affected components
| Component | Change | New props |

## UI states
| State | Trigger | Expected render |

## User flows
Numbered list of step-by-step interactions

## Mock data / Fixtures
Example data structure for development and tests
```

**Proposal:** `/f-spec` could detect if it's a UI feature (by keywords in the ticket
or the repo stack) and pre-fill these sections instead of the endpoint template.

---

## More UI proposals

**E2E tests as first-class citizens:**

Today `/f-test-impl` generates "E2E skeletons" — empty scaffolding.
Proposal: add real support for **Playwright** or **Cypress** with fixtures generated from the spec.

**Accessibility in the spec, not just in the review:**

The `ui-a11y-reviewer` runs at the end. Proposal: add an **Accessibility Requirements** section
to the spec template listing expected keyboard behavior, required ARIA roles, and announce patterns
— before implementing.

**Visual regression as an optional step:**

A `/f-visual-test` skill that runs Playwright screenshots and attaches them to the MR description.
Low cost, high value for UI reviews.

---

<!-- _class: divider -->

# 07
## Setup and general proposals

---

## Setup in 5 minutes

```bash
# 1. Install the pipeline
cd ~/team/Yield/claude-tools
./update.sh --install sdd

# 2. Configure Atlassian MCP (once per machine)
claude mcp add --transport sse atlassian https://mcp.atlassian.com/v1/sse

# 3. Configure reviewers in your project
# .claude/mr-config.json  (commit this file)
{
  "reviewers": ["username1", "username2"],
  "target_branch": "development",
  "merge_strategy": "squash"
}
```

**Optional for automatic MRs:**
```bash
brew install glab && glab auth login
```

Without `glab` the pipeline works the same — copy-paste mode.

---

## General improvement proposals

**Short term:**
- `/f-spec` from an active branch without forcing a return to `development`
- `/f-status` with visual table output (vs current plain text)
- Multi-repo `mr-config.json` — different teams, different target branches

**Medium term:**
- `/doc-changelog` — generates / updates `CHANGELOG.md` when closing each feature
- `/f-spec` reads Confluence pages as input, in addition to Jira tickets

**Long term / experimental:**
- Metrics: average spec→MR time, FAIL rate in `/f-spec-review`, severity distribution in reviews
- `/f-estimate` — estimates effort from the plan before committing to the sprint
- Feedback loop: if an MR receives many comments of the same type, the skill learns to prevent them

---

## Summary

| Stage | Skill | Artifact |
|-------|-------|----------|
| Autopilot | `/f-auto` | full pipeline non-interactive → open MR |
| Entry | `/f-start` or `/f-auto` | branch + source.md + spec |
| Plan | `/f-plan` | `.specwork/_plan/` |
| Impl | `/f-implement` + `/f-commit` | code + commits |
| Tests | `/f-test-design` + `/f-test-impl` | test files |
| Internal review | `/f-spec-review` + `/f-code-review` | `.specwork/_review/` |
| MR | `/f-mr` | `docs/specs/` ← copied + GitLab MR |
| Post-review | `/f-review-address` | resolved threads |
| Close | `/f-close` | clean workspace |

**Short path:** `/f-hotfix` → impl → `/f-commit` → `/f-mr` → `/f-close`

**Autopilot:** `/f-auto <ticket-or-text>` — one command, no prompts, stops at OQs + risk signals

**Standalone:** `/java-review` · `/doc-adr` · `/doc-catalog`

---

<!-- _class: lead -->

# Questions

**Repo:** `team/Yield/claude-tools`

```bash
./update.sh --install sdd      # install
/f-help                        # get your bearings at any point
```

> The pipeline is team code.
> If something doesn't work as expected, open an MR.
