# Service Rules

Use this file for service-level invariants that must remain true across features.
Copy it to `./.opensdd/service-rules.md` in each consumer project.

## Business Invariants

- Keep only stable domain rules (not ticket-specific behavior).
- Example: "A lead must never be pushed downstream more than once."
- Example: "A consent message must always reference the selected delivery channel."

## Fallback and Idempotency

- Define mandatory fallback behavior for external dependency failures.
- Define idempotency keys and duplicate-processing protection.
- Define atomic update boundaries when multiple writes are involved.

## Historical Constraints

- Preserve backward-compatible behavior for existing clients/events.
- Keep event semantics stable unless a versioned migration is introduced.

## Architecture Constraints

- Keep only implementation-impacting constraints.
- Example: "Use constructor injection only."
- Example: "Access external integrations through dedicated adapter/wrapper layers."

## Out of Scope (Do Not Add Here)

- Ticket-only decisions
- Temporary rollout notes
- Dates, branch names, or one-off implementation tasks
