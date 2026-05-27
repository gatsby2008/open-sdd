---
name: doc-publish
description: Publish the current project's service catalog to the central registry (default ${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/, override with $OPEN_SDD_DOC_HOME for team-shared registries), or list catalogs already in the registry. Run `/doc-publish` after `/doc-catalog`. Run `/doc-publish list` to inspect what is already registered.
argument-hint: "[list]"
allowed-tools: Read, Bash(cp:*), Bash(mkdir:*), Bash(ls:*), Bash(git rev-parse:*), Bash(test:*), Bash(stat:*)
---

# Publish Service Catalog

**Load**: `view $OPEN_SDD_ROOT/skills/doc/doc-publish/SKILL.md`

---

## Modes

| Invocation | Action |
|------------|--------|
| `/doc-publish` | **Publish mode (default)** — push the current project's `docs/service-info.md` to the central registry. |
| `/doc-publish list` | **List mode** — print the catalogs currently in `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/`, with last-modified timestamps. Read-only; does not publish. |

Reject any other argument with a usage message.

---

## Registry Path

All registry I/O resolves through a single environment variable:

```bash
REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/service-catalog"
```

- **Default** (no env var set): `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/` — identical to the original behavior. No migration needed.
- **Override**: `export OPEN_SDD_DOC_HOME=/path/to/registry-root` — e.g., a cloned GitLab repo for team-shared catalogs. The skill writes/reads under `$OPEN_SDD_DOC_HOME/service-catalog/`.

The same variable controls `/doc-query`, `/adr-publish`, and `/adr-query` (which resolve `$OPEN_SDD_DOC_HOME/adr-registry/`), so all doc registries move together.

---

## List Mode

Run when the argument is `list`. Print the registry and exit before any publish logic runs.

```bash
REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/service-catalog"

if [ ! -d "$REGISTRY" ] || ! ls "$REGISTRY"/*.md >/dev/null 2>&1; then
  echo "Service catalog registry is empty."
  echo "Run /doc-catalog then /doc-publish in a service repo to populate it."
  exit 0
fi

echo "Registered services in $REGISTRY:"
ls -lt "$REGISTRY"/*.md 2>/dev/null | while read -r line; do
  # $6 $7 $8 = mtime month/day/(year|time), $NF = path
  name="$(echo "$line" | awk '{print $NF}' | xargs basename)"
  mtime="$(echo "$line" | awk '{print $6, $7, $8}')"
  printf "  %-40s  (last updated %s)\n" "$name" "$mtime"
done
```

Output example:

```
Registered services in <registry>/service-catalog:
  consent-service.md                        (last updated May 19 14:32)
  marketing-service.md                      (last updated May 18 09:15)
  leads-service.md                          (last updated May 12 11:48)

Use /doc-query to ask cross-service questions against this registry.
```

After listing, exit. Do not proceed to the publish steps below.

---

## Publish Mode (default)

| Step | Action |
|------|--------|
| 1 | Verifies `docs/service-info.md` exists in the current project |
| 2 | Detects the service name from the catalog file or git remote |
| 3 | Copies to `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/<service-name>.md` |
| 4 | Prints confirmation |

---

## Step 1 — Check Catalog Exists

```bash
[ -f docs/service-info.md ]
```

If not found, abort:

```
docs/service-info.md not found.
Run /doc-catalog first to generate the service catalog.
```

---

## Step 2 — Detect Service Name

Try in order:

1. Read the `# <ServiceName>` heading from `docs/service-info.md` — use the first `#` line, convert to kebab-case
2. Fall back to the git remote URL — extract the repo name:
   ```bash
   git rev-parse --show-toplevel | xargs basename
   ```

Example: heading `# Leads Service` → `leads-service.md`

---

## Step 3 — Copy

```bash
REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/service-catalog"
mkdir -p "$REGISTRY"
cp docs/service-info.md "$REGISTRY/<service-name>.md"
```

---

## Step 4 — Confirm

After the copy succeeds, list every `*.md` file in the registry (not just a count — the actual file names) so the user can see what is now registered. Use this exact command to produce the list:

```bash
ls -1 "${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/service-catalog"/*.md 2>/dev/null | xargs -n1 basename | sort
```

Then print the confirmation block, substituting the real names:

```text
Published: docs/service-info.md → ${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/<service-name>.md

Registry now contains:
  consent-service.md
  leads-service.md
  marketing-service.md

Run /doc-query to ask cross-service questions.
```

Always print the full file list — never abbreviate to a count ("Registry now contains 3 catalogs") and never elide entries with "...". The user needs the explicit `<service-name>.md` names to know what is queryable.

---

## Related Skills

- `doc-catalog` — generates `docs/service-info.md` for the current service
- `doc-query` — reads all catalogs from `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/` and answers cross-service questions
