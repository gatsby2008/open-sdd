# Documentation Skills

A bundle of six skills that together form a documentation and cross-service architecture-discovery workflow. Two parallel pipelines — one for **service catalogs**, one for **ADRs** — share the same publish/query split.

## Members

| Slash command | Purpose |
|---------------|---------|
| `/doc-adr` | Capture an architectural decision as an ADR in `docs/adr/`. Modes: free text, from a Jira ticket, or from resolved Open Questions on the current branch. |
| `/doc-catalog` | Generate or refresh `docs/service-info.md` for the current microservice (Java Spring Boot or frontend). Scans controllers, listeners, clients, schedulers, and config. |
| `/doc-publish` | Publish the local `docs/service-info.md` to the central registry at `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/`. Run after `/doc-catalog`. |
| `/doc-query` | Answer cross-service architecture questions by reading the catalog registry. Run from any project once catalogs have been published. |
| `/adr-publish` | Publish the local `docs/adr/*.md` to the central registry at `${OPEN_SDD_ROOT:-~}/.opensdd/registry/adr-registry/<service>/`. Run after `/doc-adr`. |
| `/adr-query` | Answer cross-service decision-history questions by reading the ADR registry. Run from any project once ADRs have been published. |

## Workflow

```
Catalogs (one per service):
  /doc-catalog   →  writes docs/service-info.md
       │
       ▼
  /doc-publish   →  ${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/<service>.md
       │
       ▼
  /doc-query     →  cross-service architecture questions

ADRs (many per service):
  /doc-adr       →  writes docs/adr/<TICKET>-ADR-NNN-<slug>.md
       │
       ▼
  /adr-publish   →  ${OPEN_SDD_ROOT:-~}/.opensdd/registry/adr-registry/<service>/<TICKET>-ADR-NNN-*.md
       │
       ▼
  /adr-query     →  cross-service decision-history questions
```

Both pipelines follow the same shape: the `*-publish` step is run inside each service repo to keep the registry fresh; the `*-query` step reads the entire registry from anywhere.

## Registry location

All four publish/query skills resolve their registry path from a single environment variable:

```bash
REGISTRY_HOME="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}"
# service-catalog → $REGISTRY_HOME/service-catalog/
# adr-registry    → $REGISTRY_HOME/adr-registry/
```

| `OPEN_SDD_DOC_HOME` | Resolves to | Use case |
|-------------------|-------------|----------|
| not set (default) | `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/`, `${OPEN_SDD_ROOT:-~}/.opensdd/registry/adr-registry/` | Solo developer, local only — identical to the original behavior. No migration needed. |
| `~/repos/docs-registry` (any path) | `~/repos/docs-registry/service-catalog/`, `~/repos/docs-registry/adr-registry/` | Team-shared registry — e.g., a cloned GitLab repo committed and pulled by the whole team. |

Both registries always move together — there is no per-skill override. This keeps the configuration story to one variable.

## Team-shared registry (optional)

To share catalogs and ADRs across a team via a GitLab project:

### One-time setup (per developer)

```bash
# 1. Clone the team's docs registry into any path you prefer
git clone git@gitlab.com:<group>/docs-registry.git ~/repos/docs-registry

# 2. Point the skills at it (add to ~/.zshenv on macOS so non-interactive shells see it too)
echo 'export OPEN_SDD_DOC_HOME=~/repos/docs-registry' >> ~/.zshenv
source ~/.zshenv

# 3. Verify
/doc-publish list      # should list catalogs from the GitLab repo
/adr-publish list      # should list ADRs from the GitLab repo
```

### Migrating existing local data (one-time)

If you already have catalogs/ADRs under `${OPEN_SDD_ROOT:-~}/.opensdd/registry/`, copy them into the new registry (the skills do not auto-migrate):

```bash
# Copy (safer than mv until you confirm the new flow works)
mkdir -p "$OPEN_SDD_DOC_HOME/service-catalog" "$OPEN_SDD_DOC_HOME/adr-registry"
cp -r ${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/. "$OPEN_SDD_DOC_HOME/service-catalog/" 2>/dev/null
cp -r ${OPEN_SDD_ROOT:-~}/.opensdd/registry/adr-registry/.    "$OPEN_SDD_DOC_HOME/adr-registry/"    2>/dev/null

# Commit + push the seed data
cd "$OPEN_SDD_DOC_HOME"
git add service-catalog adr-registry
git commit -m "seed: initial catalogs and ADRs from <your-machine>"
git push

# Once you're confident the new flow works, clean up the originals
rm -rf ${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog ${OPEN_SDD_ROOT:-~}/.opensdd/registry/adr-registry
```

### Day-to-day flow

```bash
# In any service repo:
/doc-catalog && /doc-publish        # generate + publish catalog
/doc-adr "..." && /adr-publish      # capture + publish ADR

# Share with the team:
cd "$OPEN_SDD_DOC_HOME"
git add -A && git commit -m "publish: <what changed>" && git push

# Pull other people's updates:
cd "$OPEN_SDD_DOC_HOME" && git pull
```

### Suggested GitLab repo layout

```
docs-registry/                 ← repo root
├── README.md                  ← onboarding for the team
├── service-catalog/
│   ├── consent-service.md
│   ├── leads-service.md
│   └── ...
└── adr-registry/
    ├── consumer-portal/
    │   ├── IR-64-ADR-001-…md
    │   └── IR-64-ADR-002-…md
    └── transunion-service/
        └── MYYES-17097-ADR-001-…md
```

Conflicts are rare because each catalog is one file per service and each ADR has its own file under a service subdir. When two devs publish the same service on the same day, git's normal merge resolution applies — the files are plain markdown.

## Install

```bash
./update.sh --install doc                # full bundle
./update.sh --install doc/doc-adr        # one member
./update.sh --install doc/doc-catalog
./update.sh --install doc/doc-publish
./update.sh --install doc/doc-query
./update.sh --install doc/adr-publish
./update.sh --install doc/adr-query
```

## Integration with the SDD pipeline

`/f-mr` (in the `sdd` bundle) prints a hint suggesting `/doc-adr open-questions` when the current spec has any resolved Open Questions — those resolutions are the most common form of architectural decision worth preserving as an ADR. The other doc skills are independent of the SDD pipeline and can be run on any branch at any time.
