# ADR

Captures a technical decision as an Architecture Decision Record — a short,
immutable document that records the context, the decision, and the consequences.
Lives in `docs/adr/` alongside the code it describes.

ADRs are never edited. If a decision changes, a new ADR supersedes the old one,
preserving the full history of why the system is the way it is.

---

## Usage

```bash
# Start with a description
/doc-adr "use PostgreSQL instead of Redis for circuit breaker state"

# Extract decisions from a Jira ticket
/doc-adr MYYES-17097

# Interactive — skill asks for the decision
/doc-adr
```

---

## What It Produces

```
docs/adr/MYYES-17097-ADR-001-use-postgresql-circuit-breaker.md
```

File name format: `<TICKET>-ADR-NNN-<slug>.md` (ticket first, then 3-digit ADR number, then slug). Use `NOTICKET` as the prefix if no ticket exists. The ADR counter is service-wide — it doesn't reset per ticket.

```markdown
# ADR-003: Use PostgreSQL Instead of Redis for Circuit Breaker State

## Status
Accepted

## Context
The TLO circuit breaker needs to persist its OPEN/CLOSED state across all
service replicas so that a single Access Denied event halts traffic on every
instance immediately...

## Decision
Use PostgreSQL with a singleton row and pessimistic write lock.
Redis was ruled out because it would introduce a new infrastructure dependency
for a single use case...

## Consequences
- No new infrastructure dependency — PostgreSQL is already required
- Every TLO call incurs one extra DB read for isOpen()
- Circuit state survives restarts and replica scaling

## Related
- Jira: [MYYES-17097](https://ysgco.atlassian.net/browse/MYYES-17097)
- MR: [!127](https://gitlab.com/ysg-devs/services/transunion-service/-/merge_requests/127)
```

---

## Why ADRs in the repo

Confluence gets stale. Jira tickets get closed. The code stays.

ADRs live where the code lives — when someone reads `TloCircuitBreakerService`
and wonders "why PostgreSQL and not Redis?", the answer is one directory away.

---

## Independent of the SDD pipeline

This skill has no dependency on `.specwork/` artifacts. It can be used standalone
or alongside the SDD pipeline at any point in the development cycle.
