# SDD pipeline — state diagrams

Three views at increasing depth. The diagrams reflect the post-refactor
pipeline where `/f-start` only initializes and `/f-spec` is a separate
idempotent command (drafts the first time, refines after).

Paste any block into GitHub, the Mermaid Live Editor, or any mermaid renderer.

---

## 1. Compact (command flow)

Happy path with optional branches. Best view for a README.

```mermaid
stateDiagram-v2
    [*] --> Start
    Start: /f-start (init only)
    Start --> Spec

    Spec: /f-spec
    Spec: drafts (first call) or refines (subsequent)
    Spec --> Spec: more context\n(files, jira, text)
    Spec --> Plan: OQs resolved, medium / large
    Spec --> Implement: OQs resolved, small / obvious

    Plan: /f-plan (optional)
    Plan --> Implement

    Implement: /f-implement (N times)
    Implement --> Implement: more steps
    Implement --> TestDesign: HIGH risk
    Implement --> Commit: LOW/MED risk

    TestDesign: /f-test-design
    TestImpl: /f-test-impl
    TestDesign --> TestImpl
    TestImpl --> Commit

    Commit: /f-commit
    Commit --> Review: optional
    Commit --> MR

    Review: /f-code-review
    Review --> MR

    MR: /f-mr
    MR --> Address: reviewer comments
    MR --> Close: merged
    Address: /f-mr-address
    Address --> MR

    Close: /f-close
    Close --> [*]

    note right of Spec
        /f-spec-refine is a deprecated alias.
        Re-running /f-spec from any later
        state mutates the spec and bumps
        spec_write_timestamp.
    end note
```

---

## 2. Complete (gates + transversal commands)

Adds the strict gates (`/f-implement`'s OQ + plan-staleness checks), the
`/f-spec` re-entry points from later states, and `/f-pause` / `/f-resume`.

```mermaid
stateDiagram-v2
    direction TB
    [*] --> Start

    state "Start (/f-start)" as Start
    state "Spec (/f-spec)" as Spec
    state "Plan (/f-plan)" as Plan
    state "Implement (/f-implement)" as Implement
    state "Test Design (/f-test-design)" as TestDesign
    state "Test Impl (/f-test-impl)" as TestImpl
    state "Commit (/f-commit)" as Commit
    state "Code Review (/f-code-review)" as Review
    state "MR (/f-mr)" as MR
    state "Address (/f-mr-address)" as Address
    state "Close (/f-close)" as Close
    state "Paused" as Paused

    Start --> Spec

    Spec --> Spec: more context / unresolved OQs
    Spec --> Plan: OQs resolved · 3+ files
    Spec --> Implement: OQs resolved · 1-2 files\n(plan skip)

    Plan --> Implement: OQs resolved

    state if_oq <<choice>>
    Implement --> if_oq
    if_oq --> Implement: unresolved OQs\nor stale plan
    if_oq --> Implement: more steps
    if_oq --> TestDesign: HIGH risk
    if_oq --> Commit: LOW/MED risk

    TestDesign --> TestImpl
    TestImpl --> Commit

    Commit --> Review: optional
    Commit --> MR
    Review --> MR

    MR --> Address: reviewer threads
    Address --> MR: re-push

    MR --> Close: merged
    Close --> [*]

    Plan --> Spec: new context\n(plan staleness ahead)
    Implement --> Spec: new context\n(plan staleness ahead)

    Start --> Paused: /f-pause
    Spec --> Paused: /f-pause
    Plan --> Paused: /f-pause
    Implement --> Paused: /f-pause
    Paused --> Implement: /f-resume

    note right of Implement
        Strict gates:
        · Open Questions in spec or plan
        · plan.md older than spec.md mtime
          (or stored spec_write_timestamp)
    end note
```

---

## 3. Artifact-oriented

Same pipeline, but each state lists which files live in `.specwork/` at
that point. Transitions are the commands that create / mutate / consume them.

```mermaid
stateDiagram-v2
    direction TB

    [*] --> Pristine: new branch

    state "Pristine" as Pristine
    Pristine: .specwork/ does not exist

    state "Started" as Started
    Started: _state/state.json\n(current_step=spec)
    Started: _state/rules.json
    Started: _state/implementation-cache.json
    Started: _spec/source.md
    Started: (no spec.md — /f-spec owns it)

    state "Drafted" as Drafted
    Drafted: + _spec/spec.md (created by /f-spec\nfrom source.md + template)
    Drafted: cache updated\n(repositories, related_tests)
    Drafted: spec_write_timestamp bumped

    state "Planned" as Planned
    Planned: + _plan/plan.md
    Planned: cache seeded\n(patterns, similar_classes)

    state "Implementing" as Implementing
    Implementing: working tree mutated
    Implementing: cache appended\n(notes, similar_classes)
    Implementing: spec.md OQs may grow

    state "TestDesigned" as TestDesigned
    TestDesigned: + _test/test-design.md

    state "TestsImplemented" as TestsImplemented
    TestsImplemented: test files in working tree

    state "Committed" as Committed
    Committed: commits in git\n(artifacts unchanged)

    state "Reviewed" as Reviewed
    Reviewed: + _review/code-review.md

    state "MROpen" as MROpen
    MROpen: docs/specs/spec.md\n(published, committed)
    MROpen: branch pushed

    state "Addressing" as Addressing
    Addressing: + _review/mr-address.md

    state "Merged" as Merged
    Merged: spec lives in docs/specs/

    Pristine --> Started: /f-start
    Started --> Drafted: /f-spec\n(draft mode)
    Drafted --> Drafted: /f-spec\n(refine mode\n+ bump ts)
    Drafted --> Planned: /f-plan
    Drafted --> Implementing: /f-implement\n(skip plan)

    Planned --> Drafted: /f-spec\n(plan will go STALE)
    Planned --> Planned: /f-plan\n(refresh, idempotent)
    Planned --> Implementing: /f-implement\n[gates: OQs, staleness]

    Implementing --> Implementing: /f-implement (next step)
    Implementing --> Drafted: /f-spec\n(plan staleness ahead)
    Implementing --> TestDesigned: /f-test-design\n(HIGH risk)
    Implementing --> Committed: /f-commit\n(LOW / MED risk)

    TestDesigned --> TestsImplemented: /f-test-impl
    TestsImplemented --> Committed: /f-commit

    Committed --> Reviewed: /f-code-review\n(optional)
    Committed --> MROpen: /f-mr
    Reviewed --> MROpen: /f-mr

    MROpen --> Addressing: reviewer threads
    Addressing --> Addressing: /f-mr-address\n(per-thread loop)
    Addressing --> MROpen: re-push
    MROpen --> Merged: merge in GitHub

    Merged --> Pristine: /f-close\n(wipes .specwork/)

    note right of Implementing
        Side-effects in _progress/:
        · escalations.md (append-only,
          when retry budget exhausted)
        · context.md (optional, human-authored)
    end note

    note right of Started
        Orthogonal to all states:
        · /f-handoff → _handoff/execution-pack.{md,json}
        · /f-pause / /f-resume (stash including .specwork/)
        · /f-spec-refine → deprecated alias of /f-spec
    end note
```

### Reading notes

- Filenames assume the `<slug>-` prefix (omitted for brevity).
- What lives **outside `.specwork/`**: commits, `docs/specs/<slug>-spec.md`
  (published by `/f-mr`), eventually `docs/adr/ADR-NNNN-*.md` if `/doc-adr`
  runs.
- `/f-close` wipes the entire `.specwork/`. It keeps: commits, branch, MR,
  published docs.
- `/f-start` leaves `current_step="spec"` and writes only `source.md` plus
  state files — it does NOT create `spec.md`. `/f-spec` owns `spec.md`:
  draft mode (file missing) creates it; refine mode (file exists)
  integrates new context. `/f-spec` is also the only command that advances
  `spec → plan`, and only on the first draft when all Open Questions are
  resolved.
- The `Planned → Drafted` and `Implementing → Drafted` edges via `/f-spec`
  are the staleness trap: re-running `/f-spec` bumps `spec_write_timestamp`,
  so any existing `plan.md` becomes stale and `/f-implement` will block
  until `/f-plan` re-runs (or the plan is deleted).
