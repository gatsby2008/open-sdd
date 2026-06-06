# Open SDD (Spec-Driven Development) Pipeline

## Consolidated Report

> This report consolidates the key concepts, terminology, architecture, workflows, decisions, and lessons learned from the SDD pipeline. It has been **reconciled against the actual codebase** (`contrib/skills/sdd/`) so the stage names, artifact paths, and rules match what the tools really do today.

---

# 1. Core Philosophy

The pipeline evolved from a simple "AI coding assistant" workflow into a **Spec-Driven Development system**.

The central principle is:

> AI should not invent requirements.
> AI should implement specifications.

This led to several fundamental rules:

* Specification before implementation.
* Open Questions must be resolved before coding.
* No guessing business behavior.
* No implicit assumptions.
* Human owns the requirements.
* AI owns the implementation.

---

# 2. Evolution of the Pipeline

## Initial Stage

Traditional AI workflow:

```text
Ticket → Prompt → AI writes code
```

Problems:

* Hallucinated requirements
* Scope creep
* Unnecessary refactors
* Context pollution
* Infinite correction loops
* Difficult handoffs

## Current Model

```text
Ticket → Source → Spec → Plan → Execution Pack → Executor Model → Validation
```

The implementation model became replaceable. Any of Claude, Gemini, Copilot, Codex, DeepSeek, Qwen, or OpenCode can consume the same Execution Pack.

---

# 3. Open SDD

One of the most important architectural decisions: the pipeline is no longer Claude-specific.

```text
Specification Layer → Execution Contract → Execution Engine
```

The execution engine can be Claude Code, OpenCode, Gemini, Copilot, Codex, DeepSeek, or a future agent. This separation is what makes it an "Open SDD" architecture: the **spec is the product**, the model is an implementation detail.

---

# 4. Two Ways In: Vibe Coding vs. Full Pipeline

Not every change needs the full pipeline. Four commands are **standalone** — no `.specwork/` state, no spec, no plan, any branch, any repo:

| Command | Standalone behavior |
|---|---|
| **`/f-commit`** | Stage + run the test-coverage gate + semantic commit message |
| **`/f-mr`** | Validate + push + create the MR |
| **`/f-code-review`** | Stack-aware quality + security review of your own diff |
| **`/f-mr-review`** | Same review engine on a peer's branch or MR (read-only) |

**Vibe loop:** code freely → `/f-code-review` (optional) → `/f-commit` → `/f-mr`.

Reach for the **full pipeline** (`/f-start …`) when the change is multi-file, high-risk, or worth a durable spec.

---

# 5. Pipeline Stages

The live pipeline is a chain of `/f-*` skills. Below is the real flow; the canonical diagram lives in `contrib/skills/sdd/README.md`.

```text
/f-start ─► /f-spec ─► /f-plan ─► /f-implement (×N) ─► [/f-test-design ─► /f-test-impl]
   │                                                              │
   │ (/f-auto chains the first four, non-interactive)             ▼
   └──────────────────────────────────────────────► /f-commit ─► /f-code-review ─► /f-mr ─► /f-mr-address ─► /f-close
```

## /f-start

Initialize work. **Does not write the spec.**

* Starts from any branch; offers a new working branch (suggested / keep current / custom) or initializes in place.
* Runs `/init` (idempotent) to bootstrap agent-memory files (`AGENTS.md` / `CLAUDE.md` / `GEMINI.md`) **before** branch creation, so the model has repo context for the rest of the run. No-op if any already exists; no pipeline artifact depends on its output.
* Fetches the Jira ticket (or persists free-text input verbatim) into `source.md`.
* Loads global `AGENTS.md` + service-level `service-rules.md`, compiles them to `rules.json`.
* Initializes `implementation-cache.json`.
* **Refuses to re-initialize** over an active pipeline; **requires input** (stops with no writes if none).

Outputs (under `.specwork/`, gitignored):

```text
_state/<slug>-state.json
_state/<slug>-rules.json
_state/<slug>-implementation-cache.json
_spec/<slug>-source.md
```

Next: `/f-spec`.

## /f-spec

**Owns `spec.md`** (the implementation specification — *not* a "brief").

* **Draft mode** (no spec yet): generates `spec.md` from `source.md` + a stack-aware template, then runs triage.
* **Refine mode** (spec exists): integrates new context in place — resolves Open Questions, expands Implementation Context, appends Safe Constraints, adjusts Expected Change Scope. **Append-only** on Open Questions; refine with no args is a strict no-op.
* **Stack-aware template:** frontend projects draft from `templates/spec-frontend.md` (adds Components, Props & State, Routes, Design Reference, Accessibility Requirements); java/node/unknown use `templates/spec.md`. The seven canonical headings are identical across both, so downstream parsing is unaffected.
* Warns (does **not** delete) when `plan.md` is stale or the tree has uncommitted changes.

Canonical sections: **Summary · Behavior · Scope (in/out) · Implementation Context · Expected Change Scope · Safe Constraints · Open Questions.**

## /f-plan *(optional)*

Convert spec into an implementation strategy. Discovers target files and writes `_plan/<slug>-plan.md` (Target Files, Approach, Risks, Open Questions) and seeds the implementation cache.

* Applies six discovery heuristics (currently Java-focused): mock-consumer tests, `[infra]` exception handlers, test-naming guard, reference-update grep, risk surface, spec-consistency check.
* **Strict gate:** blocks if `spec.md` still has unresolved Open Questions.
* Goes **stale** when `spec.md` is edited after the plan (`spec.md` mtime > `plan.md` mtime) → `/f-implement` blocks until re-run or the plan is deleted.
* **Use** for 3+ file features / broad blast radius; **skip** for 1–2 file changes (`/f-implement` falls back to inline discovery).

## /f-implement (repeat N times)

Implement only what was specified — one focused step per run, inline tests, changes accumulate in the working tree (no commits between steps).

**Supported modes** (lightweight only — *there is no full mode*):

* `focused` — localized change, usually ≤ 3 files.
* `batch` — several sequential focused steps with shared context reuse.

**Strict gates (abort with no writes):**

* Unresolved `## Open Questions` in `spec.md` or `plan.md`.
* `plan.md` exists and is older than `spec.md` → re-run `/f-plan` or delete the plan.

Ends with a **complexity assessment**: low/isolated → `/f-commit`; high/multi-layer/async/business-critical → `/f-test-design`.

## /f-test-design + /f-test-impl *(optional — high-risk flow)*

* `/f-test-design` — analyze the diff, design test cases, write `_test/<slug>-test-design.md`.
* `/f-test-impl` — implement the test files; **depends on** the test-design artifact and refuses to run without it.

Both run **inside an active pipeline** after `/f-implement` and are **skippable** (you may go straight to `/f-commit`).

## /f-commit

One commit for all accumulated changes; auto-stages from `git status` when nothing is staged; generates a semantic message for approval.

* **Test-coverage gate (strict):** a changed production class (Java `src/main/*.java`, frontend `*.tsx/.ts`) with no matching test (`*Test`/`*IT`, `*.test`/`*.spec`) **blocks the commit**. Pure data/wiring types (DTOs, config, entities, barrels) are excluded. The only escape is a per-class waiver-with-reason in `_test/<slug>-coverage-waivers.json` (pipeline) or `.sdd-coverage-waivers.json` (standalone).

## /f-code-review *(optional)*

Stack-aware quality + security review of the current diff.

## /f-mr

* **Pre-push validation:** runs the test suite (via project-owned `commands/check.sh`); fails → stops, does not push.
* Builds a concise MR title/description from spec + commits.
* Optional publish of the spec to `docs/specs/` and to the central spec registry.
* Pushes and creates the MR (auto with `glab`, manual otherwise). `--skip-validation` for emergencies.

## /f-mr-review *(standalone)*

Reviews **someone else's** committed work (branch or MR) with the same engine as `/f-code-review`. **Read-only** — never checks out, switches, commits, pushes, or comments. Supports GitLab MRs (`glab`) and GitHub PRs.

## /f-handoff *(optional)*

Build a **model-agnostic execution pack** from existing spec + rules + context. Exits without changes if required artifacts are missing. Creates `_handoff/<slug>-execution-pack.md` (+ `.json` metadata).

## /f-mr-address

Work through open MR review comments thread by thread; tracks progress in `_review/<id>-mr-address.md`.

## /f-close

Wipes `.specwork/` after merge (or reset). On a feature branch, verifies MR status and offers to delete the local branch and switch back to the parent. **Never** touches the remote branch or source-tree changes outside `.specwork/`.

## Orchestrator & utilities

* **`/f-auto`** — non-interactive driver: chains `/f-start → /f-spec → /f-plan → /f-implement`, then **always pauses before `/f-commit`** for human review. After a manual `/f-commit` it auto-runs `/f-mr` and stops. **Never** runs `/f-close` or `/f-mr-address`. Hard-stops on unresolved Open Questions.
* **`/f-help`** — where am I, what's next. **`/f-status`** — compact pipeline status.
* **`/f-pause`** / **`/f-resume`** — stash/restore feature work (including `.specwork/`) without losing branch context.
* **`/f-resync`** — sync `.specwork/` artifacts after a branch rename (`--rename-branch` to rename + sync atomically).

---

# 6. Execution Pack

The portable contract between models, produced by `/f-handoff` at `.specwork/_handoff/<slug>-execution-pack.md`.

Structure:

```text
Feature Summary · Implementation Scope · Files · Dependencies ·
Rules · Acceptance Criteria · Risks · Known Blockers / Escalations
```

Why it matters: AI→AI handoff loses context. With a structured contract, `AI → Execution Pack → AI` is far more deterministic. The *Known Blockers / Escalations* section is sourced from `_progress/escalations.md`, so an external executor doesn't repeat failed attempts.

---

# 7. Open Questions — the central gate

**Open Questions are unchecked markdown checkboxes (`- [ ]`) in `spec.md`** (and optionally `plan.md`).

```text
Never implement through ambiguity.
```

Unresolved Open Questions **block `/f-plan` and `/f-implement`**. `/f-spec` is the canonical way to draft and resolve them (refine mode is append-only on the Open Questions list). Result: fewer hallucinations, wrong assumptions, rework, and scope drift.

---

# 8. Knowledge Layers: AGENTS.md vs. Service Rules

| | Scope | Location | Contents |
|---|---|---|---|
| **AGENTS.md** | Global | `~/.claude/skills/sdd/AGENTS.md` | Architectural rules, global constraints, invariants, anti-patterns, execution/safety constraints |
| **Service Rules** | Local (per service) | `./.claude/service-rules.md` (consumer repo) | Business invariants, domain rules, service constraints |

`/f-start` reads both and compiles them to `.specwork/_state/<slug>-rules.json`. A template ships at `~/.claude/skills/sdd/templates/service-rules.md`.

**AGENTS.md examples:** never bypass the service layer; always use DTO mappings; no direct repository access from controllers.
**Service Rules examples:** Consent Service is source of truth; Lead Service owns application creation.

**What does NOT belong in either:** ticket-specific logic, feature-specific requirements, temporary decisions — those go in the spec.

---

# 9. Implementation Cache

Repository memory that avoids rediscovering structure on every run.

* Initialized by `/f-start`, seeded by `/f-plan` and `/f-spec` (when files are passed).
* Path: `.specwork/_state/<slug>-implementation-cache.json`.
* Stores: repositories, common patterns, related tests, similar classes.
* Benefit: less repo scanning, lower token consumption, faster context loading.

---

# 10. Failure Matrix (Escalation Policy)

`/f-implement` classifies failures before attempting a fix instead of retrying indefinitely. Only **direct or related** failures are retry-eligible.

| Failure class | Examples | Max attempts |
|---|---|---|
| Direct implementation error | bug, compile error | **2** |
| Related test-setup error | mock/fixture issue | **1** |
| Infrastructure | Spring context, Docker, AWS, LocalStack | **0 — escalate immediately** |
| Environmental | VPN, credentials, network | **0 — escalate immediately** |
| Unrelated / ambiguous | — | **0 — escalate immediately** |

The full classification table lives in `f-implement/REFERENCE.md` § *Failure decision matrix*.

**Persistence:** every escalation **appends** a dated entry to `.specwork/_progress/escalations.md` (mutable runtime memory, append-only within a feature, wiped by `/f-close`). `/f-handoff` reads it into the execution pack. Persisting is mandatory — the on-screen summary alone is ephemeral.

---

# 11. Context Management

The pipeline evolved to fight **context pollution** (AI drifting into unrelated code, refactoring everything, losing scope).

**Context minimization:** only load what is required. Lower tokens, better focus, less hallucination.

| | Pros | Cons |
|---|---|---|
| **Minimal context** | fast, cheap, focused | can miss dependencies |
| **Broad context** | better global understanding | more hallucination, refactoring temptation, higher cost |

Token-optimization levers actually in place: `focused`/`batch` execution modes (no full mode), the implementation cache, targeted discovery over repo-wide scans, and read-only review engines that resolve a diff instead of loading the tree.

---

# 12. Human–AI Responsibility Model

| Human owns | AI owns |
|---|---|
| Business intent | Analysis |
| Requirements | Planning |
| Open Questions (answering) | Implementation |
| Final approval | Test creation |
| | Documentation |

---

# 13. Key Terminology

| Term | Meaning |
|---|---|
| SDD | Spec-Driven Development |
| Open SDD | Model-agnostic SDD |
| **Source** | Raw input captured by `/f-start` (`source.md`) — seed for the spec |
| **Spec** | Implementation specification owned by `/f-spec` (`spec.md`) |
| Open Question | Unresolved requirement — an unchecked `- [ ]` box in `spec.md` |
| Execution Pack | Portable implementation contract (`/f-handoff`) |
| AGENTS.md | Global repository/engineering knowledge |
| Service Rules | Service-specific knowledge (`.claude/service-rules.md`) |
| Implementation Cache | Repository memory artifact |
| Failure Matrix | Retry/escalation policy in `/f-implement` |
| Context Pollution | Unnecessary context growth |
| `focused` / `batch` | The two supported lightweight execution modes (no full mode) |
| Handoff | Cross-model transfer mechanism |
| Non-interactive mode | `non_interactive: true` in `state.json` (set by `/f-auto`); only allowed pauses are the OQ gate and the pre-commit handoff |

---

# 14. Artifacts (`.specwork/`, gitignored)

```text
_state/<slug>-state.json                  branch metadata + non_interactive flag
_state/<slug>-rules.json                  compiled AGENTS.md + service-rules
_state/<slug>-implementation-cache.json   repos, patterns, related tests, similar classes
_spec/<slug>-source.md                    raw Jira / free-text input (from /f-start)
_spec/<slug>-spec.md                      the specification (from /f-spec)
_plan/<slug>-plan.md                      target files, approach, risks (from /f-plan)
_test/<slug>-test-design.md               designed test cases (from /f-test-design)
_test/<slug>-coverage-waivers.json        per-class waivers for the /f-commit gate
_progress/<slug>-context.md               optional human-authored context
_progress/escalations.md                  append-only escalation log
_review/<slug>-code-review.md             review output
_review/<slug>-mr-address.md              review-comment resolution
_handoff/<slug>-execution-pack.md(.json)  handoff contract + metadata
```

Permanent (`docs/`, committed): `docs/specs/<slug>-spec.md` (published by `/f-mr`), `docs/adr/ADR-NNNN-<slug>.md` (from `/doc-adr`).

---

# 15. Most Important Discoveries

1. **Open Questions are more valuable than better prompts.** Most implementation errors came from unclear requirements, not weak models — so the pipeline turns each unknown into a hard gate.
2. **Context is a liability.** Past a point, more context ≠ better implementation.
3. **Execution Packs enable model replacement.** The specification became the product; the model became an implementation detail.
4. **Failure budgets outperform persistence.** Bounded retries (2 / 1 / 0) plus immediate escalation beat endless retrying — and escalations are persisted, not lost.
5. **Repository knowledge should be explicit.** `AGENTS.md` + Service Rules + the implementation cache reduce rediscovery and inconsistent implementations.
6. **The developer's role shifted** from *code author* to *specification author · validation authority · system designer* — the biggest conceptual change of the Open SDD initiative.

---

# Appendix — Implementation Notes (repo reality, June 2026)

* **Two repos, one behavior.** This `claude-tools` distribution and the standalone `open-sdd` repo are kept at behavioral parity: `commit`/`mr`/`code-review`/`test-*` are standalone; `plan`/`implement`/`handoff` are gated.
* **`engine/` is not yet wired.** `contrib/skills/sdd/engine/` (an artifact-gate backend) is developed and unit-tested alongside `lib/` but not yet driving the live pipeline; today's token savings from it are ~0. The two `gates.py` files (`lib/` and `engine/`) are intentionally distinct and not unified.
* **Deterministic logic lives in Python `lib/`** (`f-start.py`, `f-plan.py`, `gates.py`, `triage.py`, plus `slug.py`, `branches.py`, `paths.py`, `titles.py`, `stash.py`, `worktree.py`, `coverage.py`), covered by a stdlib `unittest` suite. CI runs it on `python:3-alpine` (busybox grep — no GNU-only flags).
* **Doc/ADR commands** (`/doc-*`, `/adr-*`) come from the standalone `doc` bundle pulled in via `.deps`, not re-shipped by SDD. They operate on `docs/` and a shared registry (`$CLAUDE_DOC_HOME`), not `.specwork/`.
