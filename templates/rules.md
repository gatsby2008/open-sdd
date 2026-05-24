# open-sdd Pipeline Rules

## Core Rules

- Never silently infer missing business behavior.
- Create Open Questions for ambiguous behavior.
- BLOCKING Open Questions stop progression.

## Scope

- Keep changes minimal and localized.
- Do not modify unrelated files.
- Avoid broad repository scans unless requested.
- Prefer existing patterns unless a significant issue exists.

## Critical Review

- Identify issues likely to:
    - break behavior
    - violate business rules
    - create data inconsistency
    - affect contracts
    - create cross-service regressions
    - introduce security or transaction risks

- Avoid optional refactors or redesigns.

## Findings Severity

- BLOCKING → stop progression
- IMPORTANT → warn only
- OPTIONAL → non-critical improvements

## Open Questions

Create only for:
- ambiguous behavior
- missing dependencies
- conflicting rules/contracts
- unsafe implementation conditions

Do not create for:
- optional refactors
- stylistic preferences
- speculative improvements

## State

- Service invariants: `.opensdd/service-rules.md` (per-project)
- Feature state: `.specwork/`
- Prefer `.specwork/_state/*.json`

## Testing

- New classes, enums, and DTOs require dedicated test classes.
- Prefer focused regression tests for changed logic.
- New endpoints require integration test coverage.
- Avoid full test suites unless requested.

## Quality Gates

- `./gradlew check` must pass before committing (`/f-commit`) and again before pushing (`/f-mr`).
- If the project is non-Gradle, detect the equivalent test command (`npm test`, `pytest`, `mvn test`, etc.).
- Failed quality checks block progression — do not commit or push on failure.
