# Publish Architecture Decision Records

Publishes the current project's `docs/adr/*.md` files (produced by `/doc-adr`) into the central registry at `~/.claude/adr-registry/<service-name>/`. The registry is then consumable by `/adr-query` for cross-service decision-history questions.

## Usage

```bash
/adr-publish          # Publish mode (default) — sync ADRs to the registry
/adr-publish list     # List mode — show every service subdir and its ADR files
```

Run `/adr-publish` after creating or updating ADRs with `/doc-adr` in each service repository.
Run `/adr-publish list` from anywhere to inspect the registry contents.

## Publish mode

1. Verifies `docs/adr/` exists and contains at least one `.md` file.
2. Detects the service name from `docs/service-info.md`'s first `# heading` or, failing that, from `git rev-parse --show-toplevel | xargs basename`.
3. **Clear-and-copy**: removes `~/.claude/adr-registry/<service-name>/` and re-creates it with every ADR from `docs/adr/`. This drops ADRs that were renamed or deleted in the repo.
4. Prints the list of synced ADRs.

```
Published 3 ADRs from docs/adr/ → ~/.claude/adr-registry/consumer-portal/

Synced:
  IR-36-ADR-002-defer-pii-until-consent-accepted.md
  MYYES-17097-ADR-001-use-postgresql-circuit-breaker.md
  NOTICKET-ADR-003-adopt-pessimistic-write-lock-for-circuit-open.md

Run /adr-query to ask questions across the registry.
```

The `rm -rf` is scoped to the **service's own subdir**: it never touches other services' ADRs.

## List mode

Read-only: prints every service subdir under `~/.claude/adr-registry/` with its ADR count and file names.

```
Registered ADRs in /Users/me/.claude/adr-registry:
  consumer-portal               (3 ADRs)
      IR-36-ADR-002-defer-pii-until-consent-accepted.md
      MYYES-17097-ADR-001-use-postgresql-circuit-breaker.md
      NOTICKET-ADR-003-adopt-pessimistic-write-lock-for-circuit-open.md
  leads-service                 (1 ADRs)
      NOTICKET-ADR-001-use-shlink-for-url-shortening.md
```

When the registry is empty or does not exist, prints a hint to run `/doc-adr` and `/adr-publish` in a service repo.

## Requirements

- `docs/adr/` must contain at least one `.md` file — run `/doc-adr` first if it does not.

## Registry location

Defaults to `~/.claude/adr-registry/<service>/`. Override with `CLAUDE_DOC_HOME` to point at a different folder (e.g., a cloned GitLab repo for team sharing) — the skill writes to `$CLAUDE_DOC_HOME/adr-registry/<service>/`. See the bundle README's *Team-shared registry* section for the full migration guide.

## Related Skills

- `/doc-adr` — creates an ADR under `docs/adr/`.
- `/adr-query` — answers cross-service decision questions against the published registry.
- `/doc-publish` — same publish/query pattern, but for service catalogs (`docs/service-info.md`).
