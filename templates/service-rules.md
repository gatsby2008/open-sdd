# Service Rules — <service-name>

## Business Invariants

- External clients (Feign, SOAP, REST adapters) must never be called directly from services — always through a dedicated processor or adapter layer that returns `Optional<T>` and swallows all exceptions.
- Soft-deleted entities (`isDeleted = true`) must never be returned to callers. Filter in repository custom queries or mapper methods — never in controllers or services.
- JPA entities must never be returned directly from controllers. Always map through MapStruct to a response DTO before returning.
- _(Add service-specific invariants here — ownership rules, atomicity contracts, circuit-breaker conditions, event semantics, etc.)_

## Fallback and Idempotency

- External calls are the only side-effects in any given operation; all other logic must be read-only where possible.
- When propagating a change to multiple external systems, wrap each call in its own `try-catch`, log on failure, never rethrow (fire-and-forget sync).
- _(Add idempotency keys, duplicate-processing guards, and rollback boundaries specific to this service.)_

## Architecture Constraints

- Constructor injection only — no `@Autowired`, no field injection, no setter injection. Use `@RequiredArgsConstructor` (Lombok) or an explicit constructor.
- External integrations must go through dedicated processor/adapter layers. No direct HTTP/SOAP/SDK calls from service classes.
- _(Add stack-specific constraints: TLS versions, auth flows, circuit-breaker state ownership, etc.)_

## Historical Constraints

- Existing public API endpoint contracts must remain unchanged unless a versioned migration is introduced.
- _(Add backward-compatibility rules specific to this service — event schemas, consumer expectations, etc.)_

## Out of Scope (Do Not Add Here)

- Ticket-only decisions
- Temporary rollout notes
- Dates, branch names, or one-off implementation tasks
