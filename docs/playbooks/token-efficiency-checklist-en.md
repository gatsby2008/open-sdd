# Token Efficiency Checklist (EN)

- Define clear `source.md` in `/f-start`; avoid ambiguous context upfront.
- Run `/f-spec` only with new context; avoid refine runs with no real changes.
- Keep `## Implementation Context` specific (exact paths/classes/endpoints).
- Run `/f-plan` when scope is >2–3 files; this cuts repeated discovery cost.
- In `/f-implement`, work in small steps; one technical objective per pass.
- Avoid side refactors during implementation; they increase cost without closing scope.
- Run `/f-test-design` + `/f-test-impl` only when the risk gate justifies it.
- Before retrying, fix root cause; avoid “trial-and-error” retry loops.
- Treat deterministic gates (`precheck`, OQ, staleness, risk-signals) as source of truth.
- If diff size grows too much, split into smaller batches/commits before continuing.
- If blocked repeatedly, escalate early (`escalations.md`) and stop wasteful token burn.
- Keep `commands/check.sh` stable to reduce MR-stage rework.
