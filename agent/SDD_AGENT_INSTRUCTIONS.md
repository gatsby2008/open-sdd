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

1. Detect current branch
2. If on `main`/`develop`, require clean tree — abort if dirty
3. Suggest feature branch name from ticket (e.g., `feature/JIRA-123`) or
   slugified free text
4. Offer: create from current HEAD / custom name / stay on current branch
5. Fetch Jira via `source lib/jira.sh && jira_write_issue_markdown` when
   configured; otherwise use free text as source
6. Create `.specwork/` directories (`_spec/`, `_state/`, `_progress/`)
7. Load rules from `lib/gates.sh` equivalent, write `rules.json`
8. Initialize `implementation-cache.json` with empty arrays
9. Write `state.json` with: branch, slug, id, ticket, input_type,
   spec_write_timestamp (current epoch seconds), base_branch
10. Draft `spec.md` from source + rules using spec template
11. If unresolved Open Questions exist, warn user
12. Output: branch created, spec path, next step recommendation

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

### /handoff

Package spec + rules + cache into a model-agnostic execution pack.

1. Check required artifacts (state, rules, spec)
2. Run Open Questions gate — abort if unresolved
3. Detect behavioral change signals in spec
4. Build execution pack at `.specwork/_handoff/<slug>-execution-pack.md`
5. Output: pack path, summary of included sections

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
