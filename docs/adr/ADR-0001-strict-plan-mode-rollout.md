# ADR-0001: Strict Plan Mode Rollout for `/f-implement`

## Status

Proposed

## Date

2026-05-31

## Context

Today, `/f-implement` treats `## Target Files` in `plan.md` as **binding but living**:
the plan is authoritative, but can be extended during implementation when a newly
required file is discovered.

This behavior exists because discovery completeness in `/f-plan` is not yet
reliably high across all cases. External execution validations repeatedly showed
real implementation scenarios where needed files were missing from `Target Files`
(for example global exception handlers, mock-consumer tests, and caller/reference
updates after endpoint/signature changes).

If strict closed-contract mode were enabled now, implementers would be blocked
by discovery misses rather than true scope violations.

## Decision

We will keep **binding but living** as the default behavior for now, and introduce
`STRICT PLAN MODE` as a staged rollout behind a feature flag.

`STRICT PLAN MODE` definition:

- If a required file is not present in `## Target Files`, `/f-implement` must stop.
- No in-flight target additions are allowed.
- User must re-run `/f-plan` (or approved override path) before continuing.

## Rollout Strategy

### Phase 0 — Baseline (current)

- Default: binding but living.
- Continue logging plan extensions (`Plan updated: +N file(s)`).

### Phase 1 — Warn-only

- Add flag: `SDD_STRICT_PLAN=warn`.
- Out-of-plan file attempts emit warnings + metrics, but do not block.
- Capture reason categories (discovery miss vs real scope expansion).

### Phase 2 — Soft-block with explicit override

- Add flag: `SDD_STRICT_PLAN=soft`.
- Out-of-plan attempts block by default.
- Allow explicit user override for the current run (audited in progress logs).

### Phase 3 — Strict default

- Set default to strict only after exit criteria are met.
- `SDD_STRICT_PLAN=off` remains temporary escape hatch during stabilization window.

## Exit Criteria to enable strict-by-default

All criteria must hold over a representative window (for example, 2–3 weeks):

1. **Low out-of-plan rate**: `Plan updated: +N file(s)` events are rare and trending down.
2. **Discovery gap closure**: known categories are addressed:
   - exception handler propagation,
   - cross-service mock-consumer updates,
   - caller/reference updates.
3. **No critical regressions** from soft-block mode in high-throughput teams.
4. **UI discovery follow-ups completed** (where applicable for frontend pipelines).

## Consequences

### Positive

- Higher determinism and reproducibility of implementation runs.
- Stronger plan-as-contract semantics.
- Better auditability of scope drift.

### Negative / Risks

- Premature strictness can cause false blocks and developer friction.
- Requires robust discovery quality before strict mode becomes default.

## Alternatives Considered

1. **Enable strict mode now**  
   Rejected: high risk of blocking legitimate work due to current discovery misses.

2. **Keep binding but living indefinitely**  
   Rejected: does not enforce contract hardening once discovery matures.

3. **Strict mode only for selected repos/services**  
   Viable transitional option; can be used during Phase 2 rollout.

## Implementation Notes

- Add strict mode handling to `/f-implement` gate logic.
- Emit structured telemetry/log lines for out-of-plan attempts.
- Keep escalation and progress artifacts aligned with mode decisions.

## Follow-up

- Review this ADR after Phase 1 data collection.
- If criteria are met, move status to Accepted and start Phase 2.
