# open-sdd

Open-source Spec-Driven Development pipeline. Framework-agnostic, LLM-agnostic.

A portable reimplementation of the SDD pipeline — originally built for Claude Code,
now decoupled to work with any LLM (Ollama, GPT, Claude, Gemini) or purely as shell scripts.

## Pipeline Flow

```
  Jira ticket or free-text description
  (start from any branch; create a new branch or continue on current)
          │
          ▼
    ┌─────────────┐
    │  /f-start   │  → pre-flight, create/select branch, write state + source + spec
    │             │  → triage: classify ticket → path.json (advisory)
    └──────┬──────┘
           │  ◄──── /f-refine    [any time — resolve Open Questions, add scope, add constraints]
           ▼              (warns if plan.md is now stale)
    ┌─────────────┐
    │  /f-plan    │  (optional) → discover target files, draft plan, seed cache
    └──────┬──────┘  ◄──── re-run after /f-refine to clear staleness
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
  low/medium           high/multi-layer
       │                   │
       ▼                   ▼
  /f-commit         /f-test-design  → design test cases
       │             /f-test-impl   → implement tests
       │             /f-commit
       └──────┬──────┘
              │  implementation complete
      ┌────────────────┐
      │ /f-code-review      │ (optional)
      └───────┬────────┘
              │
      ┌────────────────┐
      │   /f-mr        │  → push, create PR
      └───────┬────────┘
              │
      ┌────────────────────┐
      │ /f-code-review-address  │  (address review comments)
      └───────┬────────────┘
              │  merged
      ┌──────────────┐
      │  /f-close    │  → clean .specwork/
      └──────────────┘

INDEPENDENT (any branch, any time):
  /f-commit            — semantic commit messages
  /f-mr                — MR description & creation
  /f-code-review            — stack-aware quality + security review
  /f-handoff           — package artifacts for other agents

UTILITIES:
  /f-help              — where am I, what's next
  /f-status            — detailed pipeline progress
  /f-triage            — classify ticket and recommend pipeline path
  /f-pause             — stash work without switching branches
  /f-resume            — restore paused work
  /f-resync            — sync artifacts when branch was renamed
  /f-refine            — refine spec with additional context
  /f-test-design       — design test cases
  /f-test-impl         — implement test files
```

> **Open Questions** are unresolved markdown checkboxes (`- [ ]`) in `spec.md`
> (and optionally `plan.md`) that block `/f-implement` until answered.
> `/f-refine` is the canonical way to resolve them.

## Install

open-sdd is **fully self-contained** — no dependency on `~/.claude/` or any
external skill registry. Everything lives in this repo.

Registers all 18 `/f-*` commands as native opencode custom commands
(underlined, tab-completion, no trailing space needed):

```bash
git clone <repo-url> ~/team/Yield/open-sdd
./open-sdd/install.sh
```

Re-run `install.sh` after moving open-sdd or adding new commands.

### Per-project setup

In each consumer project where you want to use the pipeline:

1. Install open-sdd globally (see Install above)

The first `/f-start` auto-bootstraps `AGENTS.md`, `.opensdd/service-rules.md`,
and `.opensdd/mr-config.json` in the project.

## One-Time Setup

### Jira REST credentials (optional but recommended)

```zsh
export JIRA_BASE_URL="https://your-company.atlassian.net"
export JIRA_USER="your.email@company.com"
export JIRA_TOKEN="your-atlassian-api-token"
```

Without Jira credentials, `/f-start` falls back to free-text input.

### MR config

Project config (`.opensdd/mr-config.json`, commit this):

```json
{
  "target_branch": "development",
  "merge_strategy": "squash"
}
```

### Service rules (optional but recommended)

Copy `templates/service-rules.md` to `.opensdd/service-rules.md` and
document service-level invariants: business rules, fallback behavior,
architecture constraints, historical guarantees.

`/f-start` reads both `rules.md` (open-sdd global rules) and
`.opensdd/service-rules.md` (per-project invariants) and compiles them
into `.specwork/_state/<slug>-rules.json`.

### Doc registry (optional)

open-sdd bundles doc skills (`/doc-adr`, `/doc-catalog`, `/doc-publish`,
`/doc-query`, `/adr-publish`, `/adr-query`) that publish and query a
central registry of service catalogs and ADRs. The registry location is
controlled by:

```bash
export OPEN_SDD_DOC_HOME=/path/to/shared/registry
```

Default: `${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry/`.

---

## Pipeline Commands

### /f-start \<ticket-or-text\>

- Can start from any branch
- Offers a new working branch based on current HEAD, or stay on current branch
- Writes `.specwork/_state/<slug>-state.json`, `_spec/<slug>-source.md`,
  `_spec/<slug>-spec.md`, `_state/<slug>-rules.json`,
  `_state/<slug>-implementation-cache.json`
- Resolve `## Open Questions` before implementing
- Next: `/f-implement`

### /f-refine \<files | jira \<ticket\> | paste | free text\>

- Refines the existing spec in place — resolves Open Questions, expands
  `## Implementation Context`, appends to `## Safe Constraints`,
  adjusts `## Expected Change Scope`
- Mixed input: files + Jira ticket + free text in a single call
- **Warns** when `plan.md` is older than the new spec or when the working
  tree has uncommitted changes
- Never deletes user content, never touches `source.md` / `rules.json`,
  never modifies git state
- Use any time after `/f-start`

### /f-plan *(optional)*

- Discovers target files from spec + rules + repo state
- Applies six discovery heuristics: mock-consumer tests, `[infra]`
  exception handlers, test-naming guard, reference-update grep, risk
  surface, and spec-consistency check
- Drafts `.specwork/_plan/<slug>-plan.md` with Target Files, Approach,
  Risks, and Open Questions
- Seeds `.specwork/_state/<slug>-implementation-cache.json`
- **Gate**: blocks if spec has unresolved Open Questions
- **Staleness**: after `/f-refine` or manual spec edit, the plan goes
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

- **Pre-push validation**: runs test suite before push
  - Tests fail → stops, does not push
  - Tests pass → continues
- Builds concise MR title and description from spec + commits
- Pushes branch and creates PR via `gh` (GitHub CLI)
- Optional: `--skip-validation` for emergencies

### /f-handoff (optional)

- Package spec + rules + cache into a model-agnostic execution pack
- Use when handing off to another agent (Gemini, Copilot, Codex, Claude)
- Creates `.specwork/_handoff/<slug>-execution-pack.md` + `.json`
- Gate: no unresolved Open Questions

### /f-review-address

- Address unresolved MR comments thread by thread
- Tracks progress in `.specwork/_review/<slug>-review-address.md`

### /f-close

- Wipes `.specwork/` after merge
- Verifies MR merge status via `gh`
- Never reverts or deletes source-tree changes outside `.specwork/`

---

## Companion Skills (Doc / ADR)

Beyond the pipeline, open-sdd bundles companion skills for cross-service
documentation and architecture decisions. These load automatically when
opencode starts (from `$OPEN_SDD_ROOT/skills/doc/`, registered via install.sh):

| Command | What it does |
|---------|--------------|
| **`/doc-catalog`** | Scan the current microservice and generate `docs/service-info.md` with endpoints, integrations, and config |
| **`/doc-publish`** | Publish the catalog to the central registry (`$OPEN_SDD_DOC_HOME/service-catalog/`) |
| **`/doc-query`** | Ask cross-service questions across all registered catalogs |
| **`/doc-adr`** | Create an Architecture Decision Record in `docs/adr/` |
| **`/adr-publish`** | Publish all ADRs to the central registry (`$OPEN_SDD_DOC_HOME/adr-registry/<service>/`) |
| **`/adr-query`** | Ask decision-history questions across all registered ADRs |

The `/f-mr` command will suggest running `/doc-adr open-questions` when the
spec has resolved Open Questions worth preserving as ADRs.

**See also:** [docs/learning/doc-adr-cheatsheet.md](docs/learning/doc-adr-cheatsheet.md)

---

## Implementation Cadence

```bash
/f-implement    # code + inline tests — low complexity
/f-implement    # code + inline tests — low complexity
/f-implement    # code + inline tests — HIGH → recommends /f-test-design

/f-test-design  # design missing test cases
/f-test-impl    # implement them

/f-commit       # one commit for all accumulated changes

/f-mr           # validates tests, pushes, creates PR
```

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
| `_progress/escalations.md` | Append-only log of implementation escalations |
| `_review/<slug>-code-review.md` | Code review report (optional) |
| `_review/<slug>-review-address.md` | Review comment resolution progress |
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
│   └── SDD_AGENT_INSTRUCTIONS.md   # System prompt for any LLM
├── lib/
│   ├── gates.sh                     # Validation gates
│   ├── metrics.sh                   # Timing & token metrics (opt-in)
│   └── jira.sh                      # Jira REST client via curl
├── commands/                        # 19 pipeline commands
│   ├── check.sh
│   ├── commit.sh
│   ├── handoff.sh
│   ├── help.sh
│   ├── implement.sh
│   ├── mr.sh
│   ├── pause.sh
│   ├── plan.sh
│   ├── refine.sh
│   ├── resume.sh
│   ├── resync.sh
│   ├── code-review.sh
│   ├── review-address.sh
│   ├── start.sh
│   ├── status.sh
│   ├── test-design.sh
│   ├── test-impl.sh
│   └── triage.sh
├── templates/
│   ├── AGENTS.md                    # For opencode auto-discovery (copy to project root)
│   ├── CLAUDE.md                    # For Claude Code auto-discovery (copy to project root)
│   ├── rules.md                     # Global pipeline rules (compiled at /f-start)
│   ├── service-rules.md             # Per-project invariants (copy to .opensdd/)
│   ├── rules.json                   # Rules schema template
│   ├── spec.md                      # Spec scaffold template
│   └── mr-config.json               # MR config template
└── install.sh                       # Register /f-* commands in opencode
```

---

## Bugs fixed from the original (claude-tools)

| Bug | Fix |
|-----|-----|
| mtime gate false negative after git stash (f-pause destroys mtime) | `spec_write_timestamp` stored in `state.json`, not filesystem mtime |
| `source metrics.sh` blocked by Claude Code allowed-tools | No permission system — scripts run directly |
| Java-only heuristics silently skip Node/TS projects | Stack detection (`build.gradle`/`pom.xml` → java, `package.json` → node) with per-stack heuristics |
| Metrics "heavy" tier mislabeled | Prompt and code now agree on which skills are heavy |
| `resolve_slug()` ignored free-text slug in favor of branch name | Matches current branch against `state.json::branch` field first |

---

## Requirements

- **Bash 4+**
- **git**
- **python3** — used by `start.sh` for JSON/rules processing
- **opencode** — required only for `/f-*` command integration (via `install.sh`)
- **GitHub CLI (`gh`)** — required for `mr.sh` and `close.sh`
- **Stack-specific toolchain** — required by `check.sh` (e.g., Gradle for Java projects, npm for Node)
- **jq** — optional, for Jira integration
- **JIRA_BASE_URL**, **JIRA_USER**, **JIRA_TOKEN** — required only for
  Jira ticket fetching in `start.sh`

---

## License

MIT
