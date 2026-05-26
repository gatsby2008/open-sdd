# SDD — Key Concepts

Cross-cutting ideas that govern how the pipeline works in this project. Understand these 6 concepts and the rest derives.

| Concept | Summary |
|---------|---------|
| **AGENTS.md as dual-source** | opencode loads `AGENTS.md` directly as system instructions (full prose, section semantics). The pipeline compiles it to `rules.json` via `f-start.py` (lossy: only top-level bullets, capped at 20, no sub-bullets). Two different consumers, one source file. |
| **`.specwork/` is transient** | All pipeline state lives in `.specwork/` — it is gitignored, created by `/f-start`, wiped by `/f-close`. It is working memory, not historical record. Never commit it. |
| **Open Questions gate progression** | Any unchecked `- [ ]` under `## Open Questions` in `spec.md` or `plan.md` blocks `/f-implement` and downstream commands. BLOCKING OQs stop the pipeline. Resolve them via `/f-spec-refine` or direct spec edits. |
| **Plan staleness gate** | If `plan.md` exists and `spec.md` is newer, `/f-implement` blocks. Re-run `/f-plan` or delete `plan.md` to fall back to inline discovery. The gate is strict — no silent fallback. |
| **Quality gates** | `bash commands/check.sh` must pass before `/f-commit` and `/f-mr`. Failed checks block progression. The project defines its own checks in that script. |
| **Service-rules are a convention** | `.opensdd/service-rules.md` is not auto-discovered by opencode. The project's `AGENTS.md` tells the model to load it when present. It is a pipeline convention, not a framework feature. |

---

**See also:**
- [open-sdd-architecture.md](open-sdd-architecture.md) — architectural overview
- [sdd-pipeline-cheatsheet.md](sdd-pipeline-cheatsheet.md) — command lookup
- [doc-adr-cheatsheet.md](doc-adr-cheatsheet.md) — service catalog + ADR commands
- [sdd-flashcards.md](sdd-flashcards.md) — deep-dive Q&A
