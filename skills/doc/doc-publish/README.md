# Publish Service Catalog

Publishes the current project's `docs/service-info.md` (produced by `/doc-catalog`) into the central registry at `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/`. The registry is then consumable by `/doc-query` for cross-service architecture questions.

## Usage

```bash
/doc-publish          # Publish mode (default) — push current project's catalog
/doc-publish list     # List mode — show what is already in the registry
```

Run `/doc-publish` after `/doc-catalog` in each service repository.
Run `/doc-publish list` from anywhere to inspect the registry contents.

## Publish mode

1. Verifies `docs/service-info.md` exists in the current project.
2. Detects the service name from the catalog's first `# heading` or, failing that, from `git rev-parse --show-toplevel | xargs basename`.
3. Copies the catalog to `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/<service-name>.md`.
4. Prints the updated registry contents.

```
Published: docs/service-info.md → ${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/<service>.md

Registry now contains:
  consent-service.md
  leads-service.md
  marketing-service.md

Run /doc-query to ask cross-service questions.
```

## List mode

Read-only: prints the catalogs in `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/` with last-modified timestamps. Useful for spotting stale catalogs that may need a refresh in their source project.

```
Registered services in <registry>/service-catalog:
  consent-service.md                        (last updated May 19 14:32)
  marketing-service.md                      (last updated May 18 09:15)
  leads-service.md                          (last updated May 12 11:48)
```

When the registry is empty or does not exist, prints a hint to run `/doc-catalog` and `/doc-publish` in a service repo.

## Requirements

- `docs/service-info.md` must exist — run `/doc-catalog` first if it does not.

## Registry location

Defaults to `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/`. Override with `OPEN_SDD_DOC_HOME` to point at a different folder (e.g., a cloned GitLab repo for team sharing) — the skill writes to `$OPEN_SDD_DOC_HOME/service-catalog/`. See the bundle README's *Team-shared registry* section for the full migration guide.

## Related Skills

- `/doc-catalog` — generates the per-service catalog this skill publishes.
- `/doc-query` — answers cross-service questions against the published registry.
