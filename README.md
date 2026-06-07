# open-sdd

**open-sdd makes AI coding agents safer** — by forcing them to work from specs,
respect unresolved questions, validate changes, and preserve execution context
across handoffs.

> A portable, framework- and LLM-agnostic Spec-Driven Development pipeline that
> turns Jira tickets or free-text requirements into gated, repeatable
> implementation workflows for AI coding agents (Ollama, GPT, Claude, Gemini) —
> or purely as shell scripts.

Open-source. Self-contained. Everything lives in this repo.

---

## Install

open-sdd is **fully self-contained**. Registers all 29 commands (20 pipeline + 9
doc/adr) as custom commands with tab-completion:

```bash
git clone <repo-url> ~/team/Yield/open-sdd
./open-sdd/install.sh
```

Re-run `install.sh` after moving open-sdd or adding new commands.

Per-project setup, Jira credentials, MR config, the validation script, and full
platform/Windows requirements live in **[docs/setup.md](docs/setup.md)**.

---

## Quickstart

### Just want to code? (vibe coding)

You don't need the full pipeline to get the quality helpers. Three commands are
**standalone** — they work on any branch with no setup, no spec, no pipeline:

| Command | What it does standalone |
|---------|-------------------------|
| **`/f-commit`** | Semantic commit message |
| **`/f-mr`** | MR description & creation |
| **`/f-code-review`** | Stack-aware quality + security review of your own diff |
| **`/f-undo`** | Discard uncommitted changes — reversible (`--restore` to recover, `--hard` to force) |

The vibe loop: code freely → `/f-code-review` (optional) → `/f-commit` → `/f-mr`
(and `/f-undo` to roll back uncommitted changes at any point).
See [docs/learning/vibe-coding.md](docs/learning/vibe-coding.md).

### Full pipeline

Reach for the spec-driven pipeline when the change is multi-file, high-risk, or
worth a durable spec:

```bash
/f-start MYYES-123     # or: /f-start "fix duplicate leads when applicationId is null"
/f-spec                # draft the spec from the captured source
/f-plan                # (optional) discover target files + draft a plan
/f-implement           # implement one focused step (repeat N times)
/f-commit              # one commit for all accumulated changes
/f-mr                  # validate, push, create the MR
```

Or drive it non-interactively to the pre-commit handoff in one call:

```bash
/f-auto "summary: … behaviour: … scope: … safe constraints: …"
```

---

## Documentation

| Doc | Contents |
|-----|----------|
| **[docs/pipeline.md](docs/pipeline.md)** | Full flow diagram, per-command reference, companion doc/adr commands, cadence, context switching, and how to give good input |
| **[docs/concepts.md](docs/concepts.md)** | Open Questions, gates, implementation cache, handoff, artifacts (`.specwork/` / `.opensdd/`), stack awareness & frontend support |
| **[docs/setup.md](docs/setup.md)** | Per-project setup, one-time configuration (Jira, MR config, `check.sh`), full requirements, Windows/WSL2, troubleshooting, and repo structure |

---

## Notes

- `/f-help` — where am I, what's next.
- `/f-status` — detailed pipeline progress.
- For requirements changes, run `/f-spec` instead of editing the spec by hand.

---

## License

MIT