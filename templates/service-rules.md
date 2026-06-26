# <Service Name> — Business Invariants

> **Ownership:** <service-name> service. These invariants apply regardless of which file is being edited.

## Key concepts

| Concept | Source of truth | Notes |
|---------|----------------|-------|
| _(Add service-specific domain keys here)_ | | |

## Invariants

- **Feign clients are never called directly from services** — always through a Processor wrapper (`*Processor`) that returns `Optional<T>` and swallows all exceptions.

- **Soft-deleted entities (`isDeleted = true`) must never be returned to callers.** Filter in repository custom queries (`isDeletedFalse`) or in mapper methods — never in controllers or services.

- **JPA entities are never returned directly from controllers.** Always map through MapStruct to a DTO before returning.

- **Constructor injection only** — no `@Autowired`, no field injection, no setter injection. Use `@RequiredArgsConstructor` (Lombok) or an explicit constructor.

- **Fire-and-forget external sync** — when propagating a change to multiple external systems, wrap each call in its own `try-catch`, log on failure, never rethrow.

- _(Add service-specific invariants below — ownership rules, idempotency contracts, event semantics, etc.)_
