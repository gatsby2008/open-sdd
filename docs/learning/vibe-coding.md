# Vibe coding with open-sdd

You don't always want the full spec-driven pipeline (`/f-start` → `/f-spec` →
`/f-plan` → `/f-implement`). Sometimes you just want to code — hack, iterate,
follow your nose — and still get the *quality helpers*: a test-gated semantic
commit, a clean MR, and a pre-push review.

open-sdd has three **standalone** commands for exactly this. They need **no
pipeline state** (`.specwork/`), no spec, no plan. They work on any branch, any
time, in any repo — even one that has never seen `/f-start`.

| Command | What it does standalone | Needs pipeline? |
|---------|-------------------------|-----------------|
| **`/f-commit`** | Stage + run the test gate + semantic commit message | No |
| **`/f-mr`** | Validate + push + open the MR | No |
| **`/f-code-review`** | Stack-aware quality + security review of your diff | No |

Everything else (`/f-start`, `/f-spec`, `/f-plan`, `/f-implement`, `/f-handoff`,
`/f-test-design`, `/f-test-impl`, `/f-status`, `/f-pause`, `/f-resume`,
`/f-close`, `/f-resync`) **requires** an active pipeline and is not part of the
vibe-coding flow.

---

## The vibe loop

```
1. branch + code freely        (git switch -c feature/whatever; edit, edit, edit)
2. /f-code-review              ← optional: catch bugs/security before you commit
3. /f-commit                   ← test gate + semantic commit
4. /f-mr                       ← push + open MR
```

No spec to write, no Open Questions to resolve, no plan to keep fresh. Just the
helpers when you want them.

---

## How each behaves without a pipeline

### `/f-commit` — test-gated semantic commit
- **Auto-stages** tracked changes if nothing is staged (asks first when
  interactive; auto-stages when not).
- Runs the **quality gate**: `commands/check.sh` (project-local override) or the
  stack-detecting default (`./gradlew check`, `mvn verify`, `pytest`, `npm test`,
  `go test ./...`, `cargo test`, …). A non-zero exit **stops the commit**.
- Builds the message from the **branch**, not a spec:
  - Ticket parsed from the branch name (`feature/JIRA-123-foo` → `JIRA-123`).
  - `[JIRA-123] feat: <slug>` — or `feat: <slug>` when there's no ticket.
  - You approve / edit / abort before it commits.
- Pipeline-only extras (writing `checked_sha`/commit SHA into `state.json`) are
  simply skipped when there's no state.

### `/f-mr` — push + open MR
- **Guards** against meaningless MRs: aborts on the default branch, or when the
  branch has no commits beyond its base.
- Runs the test gate before pushing (skips it only if `/f-commit` already
  validated this exact HEAD — which doesn't happen in pure vibe mode, so it
  validates).
- Detects the host from `origin`: **`gh`** for GitHub, **`glab`** for GitLab.
  Override with `OPEN_SDD_MR_PROVIDER=github|gitlab` (needed for self-hosted
  GitLab). Needs an `origin` remote and the matching CLI installed.
- Builds a concise title + description from the commits.
- `--skip-validation` for emergencies.

### `/f-code-review` — review your diff
- Reviews `git diff HEAD` (staged + unstaged). Errors out if there's nothing to
  review.
- Stack-aware (Java / Node) quality + security pass, test-coverage check
  (modified classes should have updated tests), and pack hints (JPA,
  concurrency, API contracts, logging).
- Writes the report to `.specwork/_review/<slug>-code-review.md` (it creates
  `.specwork/` just for that file — it's gitignored, harmless).
- `--recheck` compares against the previous report.

---

## What you give up (and when to graduate)

Vibe mode trades away everything the spec pipeline buys you:
- No **spec** → no shared definition of done, no triage, no Open Questions gate.
- No **plan** → no target-file discovery, no risk surface, no reference-update
  scan.
- No **execution memory** (`.specwork/` cache, escalations, handoff packs).

That's the right trade for small, obvious, low-risk changes. Reach for the full
pipeline (`/f-start …`) when the change is **multi-file, high-risk, or worth a
durable spec** — auth, migrations, event flows, breaking API changes, or
anything you'd want a teammate (or another agent via `/f-handoff`) to pick up.

You can also **start vibe and graduate**: if a quick change grows, run
`/f-start` to wrap a pipeline around the branch you're already on.

---

## Requirements (vibe subset)

- **git** + a stack toolchain for the test gate (`check.sh`).
- **`gh`** (GitHub) or **`glab`** (GitLab) for `/f-mr`.
- No Jira, no `.opensdd/` config, no `.specwork/` needed.
