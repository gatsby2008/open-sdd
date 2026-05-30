# Doc / ADR Registry — Command Reference

Command-by-command reference for the documentation and architecture-decision tooling. Two registries: one for service catalogs (architecture queries), one for ADRs (decision history).

## Service Catalog

| Command | What it does / When to use |
|---------|---------------------------|
| **`/doc-catalog`** | Scan the current microservice (Java Spring Boot or frontend) and generate/update `docs/service-info.md` with endpoints, integrations, dependencies, config. Run after adding an endpoint or when the catalog is stale. |
| **`/doc-publish`** | Publish the current `service-info.md` to the central registry (`$OPEN_SDD_DOC_HOME/service-catalog/`, default `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/`). Use `list` to inspect what is registered. |
| **`/doc-query "question"`** | Read all catalogs in the registry and answer cross-service queries: *"Who consumes the LeadCreated event?"*, *"What services call /api/v1/consent?"* |

## ADRs

| Command | What it does / When to use |
|---------|---------------------------|
| **`/doc-adr`** | Create an ADR (Architecture Decision Record) in `docs/adr/<ticket>-ADR-<NNN>-<slug>.md`. Use when a significant technical decision was made (library, infrastructure, pattern, security). |
| **`/adr-publish`** | Publish all ADRs from the current project to the central registry (`$OPEN_SDD_DOC_HOME/adr-registry/<service>/`). Clear-and-copy: replaces the entire service subdir. |
| **`/adr-query "question"`** | Read all ADRs in the registry and answer decision queries: *"Why did transunion-service pick PostgreSQL over Redis for circuit-breaker state?"*, *"What ADRs are superseded?"* |

## Environment

| Variable | Effect |
|----------|--------|
| `$OPEN_SDD_DOC_HOME` | Overrides the registry root for team-shared registries (e.g., a cloned GitLab repo). Affects all four doc skills: `/doc-publish`, `/doc-query`, `/adr-publish`, `/adr-query`. |

---

**See also:**
- [open-sdd-architecture.md](open-sdd-architecture.md) — architectural overview
- [sdd-pipeline-cheatsheet.md](sdd-pipeline-cheatsheet.md) — pipeline command lookup
- [sdd-key-concepts.md](sdd-key-concepts.md) — cross-cutting concepts
- [sdd-flashcards.md](sdd-flashcards.md) — deep-dive Q&A
- [VIBE-CODING.md](vibe-coding.md) — standalone commands without pipeline
