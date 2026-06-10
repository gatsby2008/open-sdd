# Constraint-Oriented Spec-Driven Development Pipeline

## Executive Summary

A lightweight, constraint-oriented development pipeline for AI-assisted software engineering workflows. The pipeline is a focused execution system optimized for:

* low token consumption
* deterministic execution
* bounded autonomy
* persistent operational memory
* ambiguity management
* multi-model execution handoff
* human-supervised escalation

**See also:**
- [README.md](README.md) — learning docs index and recommended reading order
- [sdd-pipeline-cheatsheet.md](sdd-pipeline-cheatsheet.md) — pipeline command lookup
- [specwork-artifacts.md](specwork-artifacts.md) — `.specwork/` artifact contract
- [sdd-key-concepts.md](sdd-key-concepts.md) — cross-cutting concepts
- [sdd-flashcards.md](sdd-flashcards.md) — deep-dive Q&A on pipeline mechanics
- [doc-adr-cheatsheet.md](doc-adr-cheatsheet.md) — service catalog + ADR commands

---

# Core Philosophy

The pipeline is built on constraint-oriented engineering orchestration rather than autonomous AI coding.

Key principle:

> Missing constraints are a larger problem than missing intelligence.

The system prioritizes:

* persistent invariants
* execution boundaries
* ambiguity detection
* focused context
* reusable machine state

over:

* massive prompts
* broad repository scans
* uncontrolled autonomous reasoning

---

# Core Components

## 1. Two-Layer Architecture

The pipeline is a **two-layer system**: thin bash orchestrators over a Python decision engine.

### Bash layer (`commands/*.sh`)

One script per `/f-*` command. Each script:
- Resolves `ENGINE_ROOT` from its own location
- Calls the Python engine for every **decision** (gates, slug resolution, triage, plan state)
- Handles only **I/O and interaction** (printing, prompts, `git`, `gh`/`glab`)
- Is independently runnable and self-gating — there is **no state machine**

### Python engine (`engine/`)

Pure Python with no git side effects. Key modules:

| Module | Responsibility |
|--------|---------------|
| `cli.py` | Single dispatch entry point — maps 11 subcommands to `cmd_*` handlers |
| `gates.py` | All preconditions: `resolve_slug`, `require_specwork`, `check_open_questions`, `check_plan_staleness`, `detect_stack`, `detect_risk_signals` |
| `state.py` | `PipelineState` dataclass (17 fields + 8 computed properties) with load/save |
| `persistence.py` | Typed read/write helpers for each artifact under `.specwork/` |

Commands output machine-readable tokens (`SPECWORK_OK`, `GATES_PASSED`, `UNRESOLVED_OQS`, JSON payloads) that the bash layer greps on.

---

## 2. Context Engineering Instead of Prompt Expansion

The design eliminates repeated context reconstruction through reusable machine-readable state.

Problems addressed:

* repeated markdown rereads
* repeated repository scans
* repeated feature rediscovery
* broad autonomous exploration

The solution uses:

* reusable machine-readable state
* persistent rule storage
* focused execution artifacts
* context isolation

This enables a shift from prompt-heavy orchestration to persistent state-driven execution.

---

## 3. Persistent Rule System

The pipeline uses persistent rule layers:

```text
repo-root/
  .opensdd/
    service-rules.md
```

Purpose:

* preserve business invariants
* avoid repeated rediscovery
* reduce ambiguity
* improve consistency across implementations

Examples:

* idempotency rules
* fallback lookup behavior
* duplicate prevention
* service-specific architectural constraints

This is the pipeline's persistent operational memory.

**Compilation**: at `/f-start`, the project's pipeline instructions + `.opensdd/service-rules.md` are compiled into `.specwork/_state/<slug>-rules.json`. Compilation is lossy: regex `(?m)^- (.+)$` captures only top-level bullets, capped at 20. The LLM reads both files directly for full semantics.

---

## 4. Structured State Management

The pipeline uses machine-readable state artifacts:

```text
.specwork/
  _state/
    <slug>-state.json
    <slug>-rules.json
    <slug>-implementation-cache.json
    <slug>-path.json
```

`path.json` is written by `engine triage <slug>` (runs after `/f-spec` first draft, NOT during `/f-start`). It records the recommended pipeline path based on ticket complexity analysis.

These artifacts are the reusable execution source for downstream commands.

Benefits:

* deterministic execution
* lower token consumption
* reduced markdown rereads
* reusable compact context

---

## 5. Stack Detection

`detect_stack()` in `engine/gates.py` checks the project root for well-known build files:

| Detected file(s) | Returns |
|-----------------|---------|
| `build.gradle` / `build.gradle.kts` / `pom.xml` | `java` |
| `package.json` | `node` |
| None of the above | `unknown` |

Every command script calls `engine detect-stack` to switch heuristics:

- **java**: Spring Boot patterns (Exception handlers, ControllerAdvice, JUnit/Mockito test layout)
- **node**: Jest/Vitest mock patterns, `__tests__/` test detection, Express/NestJS infra

---

## 6. Execution Specs

The pipeline uses lightweight execution specs instead of heavy requirements documents.

Generated by: `/f-spec` (draft mode — first call). Refined by subsequent `/f-spec` calls.

Artifacts:

```text
.specwork/_spec/<slug>-spec.md
.specwork/_spec/<slug>-source.md
```

The spec structure (8 top-level sections):

```markdown
## Summary
## Scope (### In scope / ### Out of scope)
## Behavior
## Implementation Context
## Expected Change Scope
## Safe Constraints (### Safe / ### Unsafe)
## Open Questions
```

Benefits:

* reduced ambiguity
* reduced prompt size
* easier execution handoff
* improved implementation focus

---

## 7. Open Questions as an Execution Gate

Ambiguity is formalized through Open Questions.

Key rule:

```text
Unknown behavior becomes an Open Question.
```

Unresolved Open Questions block implementation.

This prevents:

* silent business-rule inference
* speculative implementations
* architectural drift

Open Questions use the format `- [ ] **#N** <question>` in `spec.md` (and optionally in `plan.md`). The `check_open_questions` gate scans both files for any unchecked checkbox under the `## Open Questions` heading.

---

## 8. Optional Planning

Planning is optional and lightweight.

Plans are stored at `.specwork/_plan/<slug>-plan.md`.

The `/f-plan` command runs 6 discovery heuristics:

1. **infra**: cross-cutting infrastructure files (exception handlers, error boundaries)
2. **mock-consumer**: test files that mock discovered classes
3. **test-naming guard**: resolves expected test paths from source files
4. **reference-update grep**: symbols marked for rename/removal in the spec
5. **spec consistency**: detects contradictory requirements
6. **risk surface**: hard keyword matches for risk signals

Plans are marked **stale** when `plan.md` is older than the stored `spec_write_timestamp` from `state.json`. The staleness gate blocks `/f-implement` until `/f-plan` re-runs or `plan.md` is deleted (falling back to inline discovery).

---

## 9. Focused Implementation Execution

Implementation uses bounded focused execution:

* one-time context loading
* no repeated scans
* focused regression testing
* detection of already implemented behavior
* utility reuse detection

Strict gates: spec must exist, no unresolved OQs, plan must not be stale. Bounded retry: 2 direct attempts, 1 setup-reset attempt, then escalation to human review. Failures are logged to `.specwork/_progress/escalations.md`.

---

## 10. Human-Enriched Specs

The pipeline supports two workflows:

### A. Vague Ticket Flow

```text
/f-start <ticket-or-text>
/f-spec
/f-plan (optional)
/f-implement
```

### B. Enriched Spec Flow

```text
/f-start <detailed-text>
/f-spec <additional-context>
/f-plan (optional)
/f-implement
```

Core insight:

```text
high-quality human constraints outperform autonomous AI discovery
```

---

## 11. Non-Interactive Autopilot (`/f-auto`)

`/f-auto` runs the pipeline up to implementation without bash prompts:

```text
/f-start → /f-spec → OQ check → /f-plan → /f-implement → (handoff)
```

It sets `SDD_NON_INTERACTIVE=1` to skip the routine bash prompts. Branch confirmation still happens: when a human drives it, `start.sh`'s interactive A/B/C prompt fires (it runs whenever no `--choose/--branch/--keep` flag is passed and stdin is a terminal); when the agent drives it, the agent confirms the branch in chat and then calls `start.sh` with an explicit `--choose A`/`--branch`/`--keep`. It then runs straight through `/f-spec → /f-plan → /f-implement → /f-commit → /f-mr` and stops at the open MR, pausing for human input at only two points:

- **Unresolved Open Questions** (after `/f-spec`): hard stop — asks the user to resolve them, then re-run.
- **Risk-signal test gate** (after `/f-implement`): only when the spec touched a risk area, it asks whether to run the optional `/f-test-design` + `/f-test-impl` steps before committing. With no risk signals it does not pause — it proceeds straight to `/f-commit`.

It does **not** stop before `/f-commit`. `/f-commit` auto-continues to `/f-mr` (via pipeline state) and the run ends at the open MR. `/f-auto` never runs `/f-close` (post-merge) or `/f-mr-address` (needs human review comments).

---

## 12. Portable Execution Contracts

The pipeline provides model-agnostic handoff via:

```text
/f-handoff
```

Purpose:

* create portable execution contracts
* enable multi-model execution
* separate context preparation from implementation

Generated artifact:

```text
.specwork/_handoff/<slug>-execution-pack.md
```

The execution pack includes:

* spec and source
* relevant rules
* execution constraints
* focused context
* testing expectations
* stop conditions

This enables workflows such as:

```text
Claude → prepares execution pack
Gemini → implements
Claude → validates/fixes tests
```

---

## 13. Risk Signals

The pipeline has a deterministic risk signal system (`detect_risk_signals` in `engine/gates.py`) that scans the spec for hard keyword matches:

| Signal | Keywords |
|--------|---------|
| `db-migration` | migration, flyway, liquibase, alter table, create table |
| `auth-security` | authentication, oauth, jwt, password hash |
| `breaking-api` | breaking change, remove endpoint, change response format |
| `data-destructive` | delete data, purge, wipe, production data |
| `concurrency` | `@transactional`, distributed transaction, race condition |

These are **not** the fuzzy triage tier — they are deterministic regex matches used by `/f-auto` to decide whether to pause for optional test steps. The `engine risk-signals <slug>` subcommand prints matching signals line by line.

---

## 14. Retry Budget and Escalation Policies

Agents cannot reliably detect real stagnation, especially in:

* integration tests
* infrastructure failures
* Spring context issues
* container orchestration
* environment configuration

The pipeline enforces bounded retries:

```text
maximum retry attempts per failure area
```

When exceeded:

* stop execution
* summarize failures
* escalate to human review

This prevents:

* runaway execution loops
* token waste
* destructive retries
* uncontrolled refactoring

Escalations are logged at `.specwork/_progress/escalations.md`.

---

## 15. Human-Supervised Execution

The pipeline uses human-supervised bounded execution.

The human is responsible for:

* architectural decisions
* ambiguity resolution
* escalation handling
* business validation

The AI handles:

* constrained implementation
* focused execution
* repetitive engineering work
* deterministic transformations

---

## 16. Vibe Coding (Standalone Commands)

Four commands work on **any branch with no pipeline setup** — no `.specwork/`, no spec, no plan:

| Command | Purpose |
|---------|---------|
| `/f-commit` | Stage + run quality gate + semantic commit message |
| `/f-mr` | Validate tests + push + open MR |
| `/f-code-review` | Stack-aware quality + security review of your own diff |
| `/f-mr-review` | Stack-aware quality + security review of a peer's branch or MR |

See [VIBE-CODING.md](vibe-coding.md) for the full workflow.

---

## 17. Final Architecture

```text
repo-root/
  .opensdd/
    service-rules.md
    mr-config.json

  .specwork/
    _spec/
      <slug>-spec.md
      <slug>-source.md

    _plan/
      <slug>-plan.md
      <slug>-plan.json

    _state/
      <slug>-state.json
      <slug>-rules.json
      <slug>-implementation-cache.json
      <slug>-path.json

    _test/
      <slug>-test-design.md

    _progress/
      escalations.md

    _review/
      <slug>-code-review.md
      <slug>-mr-address.md
      <slug>-peer-review.md

    _handoff/
      <slug>-execution-pack.md
      <slug>-execution-pack.json

```

---

## Artifact Reference

Moved to: [specwork-artifacts.md](specwork-artifacts.md)

Use that document as the source of truth for:

- folder-level purpose (`_state`, `_spec`, `_plan`, `_progress`, `_review`, `_handoff`, `_test`),
- producers/consumers per artifact,
- required vs optional files,
- and common confusion points (for example why `_progress/` is often empty).

---

## System Properties

The system is:

```text
constraint-oriented engineering orchestration
```

Key characteristics:

* lightweight
* deterministic
* reusable
* observable
* bounded
* model-agnostic
* escalation-aware

The design relies on:

* context engineering
* state reuse
* ambiguity management
* execution constraints
* bounded autonomy

---

## Design Principles

### 1. Context engineering matters more than prompt wording

### 2. Missing constraints are more dangerous than missing intelligence

### 3. Persistent operational memory dramatically improves execution quality

### 4. Human-enriched specs outperform autonomous requirement discovery

### 5. Bounded execution is safer and more efficient than unrestricted autonomy

### 6. Portable execution contracts enable multi-model orchestration

### 7. Retry limits and escalation policies are essential for real-world engineering workflows

### 8. Non-interactive autopilot enables CI-like workflows without sacrificing ambiguity management

### 9. Vibe coding (no pipeline) meets the user where they are — low ceremony for simple changes

---

## Final Philosophy

```text
Human decides.
AI executes constrained work.
Unknowns become questions.
Persistent rules guide execution.
Context stays focused.
Execution remains bounded.
```

Primary pipeline references:

* Full protocol: [`agent/PIPELINE.md`](../../agent/PIPELINE.md)
* Pipeline init: [`/f-start`](../../commands/start.sh) (writes source.md only; spec.md is created by /f-spec)
* Spec draft + refine: [`/f-spec`](../../commands/spec.sh)
* Implementation plan: [`/f-plan`](../../commands/plan.sh)
* Implementation: [`/f-implement`](../../commands/implement.sh)
* Commit: [`/f-commit`](../../commands/commit.sh)
* Merge request: [`/f-mr`](../../commands/mr.sh)
* Execution handoff: [`/f-handoff`](../../commands/handoff.sh)
* Non-interactive autopilot: [`/f-auto`](../../commands/auto.sh)
* Vibe coding (no pipeline): [`docs/learning/vibe-coding.md`](vibe-coding.md)
