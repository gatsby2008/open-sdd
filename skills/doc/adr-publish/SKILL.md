---
name: adr-publish
description: Publish the current project's Architecture Decision Records (docs/adr/*.md) to the central registry (default ~/.claude/adr-registry/<service-name>/, override with $CLAUDE_DOC_HOME for team-shared registries), or list ADRs already in the registry. Run `/adr-publish` after creating ADRs with `/doc-adr`. Run `/adr-publish list` to inspect what is already registered.
argument-hint: "[list]"
allowed-tools: Read, Bash(cp:*), Bash(mkdir:*), Bash(rm:*), Bash(ls:*), Bash(git rev-parse:*), Bash(test:*), Bash(find:*)
---

# Publish Architecture Decision Records

---

## Modes

| Invocation | Action |
|------------|--------|
| `/adr-publish` | **Publish mode (default)** — sync the current project's `docs/adr/*.md` to the central registry. |
| `/adr-publish list` | **List mode** — print every service subdir in `~/.claude/adr-registry/` and its ADR files. Read-only. |

Reject any other argument with a usage message.

---

## Registry Path

All registry I/O resolves through a single environment variable:

```bash
REGISTRY="${CLAUDE_DOC_HOME:-$HOME/.claude}/adr-registry"
```

- **Default** (no env var set): `~/.claude/adr-registry/` — identical to the original behavior. No migration needed.
- **Override**: `export CLAUDE_DOC_HOME=/path/to/registry-root` — e.g., a cloned GitLab repo for team-shared ADRs. The skill writes/reads under `$CLAUDE_DOC_HOME/adr-registry/<service-name>/`.

The same variable controls `/doc-publish`, `/doc-query`, and `/adr-query` (which resolve `$CLAUDE_DOC_HOME/service-catalog/` and `$CLAUDE_DOC_HOME/adr-registry/`), so all doc registries move together.

---

## List Mode

Run when the argument is `list`. Print the registry and exit before any publish logic runs.

```bash
REGISTRY="${CLAUDE_DOC_HOME:-$HOME/.claude}/adr-registry"

if [ ! -d "$REGISTRY" ] || [ -z "$(ls -A "$REGISTRY" 2>/dev/null)" ]; then
  echo "ADR registry is empty."
  echo "Run /doc-adr to create ADRs, then /adr-publish in a service repo to populate it."
  exit 0
fi

echo "Registered ADRs in $REGISTRY:"
for dir in "$REGISTRY"/*/; do
  [ -d "$dir" ] || continue
  service="$(basename "$dir")"
  count="$(ls -1 "$dir"*.md 2>/dev/null | wc -l | tr -d ' ')"
  printf "  %-30s  (%s ADRs)\n" "$service" "$count"
  ls -1 "$dir"*.md 2>/dev/null | xargs -n1 basename | sort | sed 's/^/      /'
done
```

Output example:

```
Registered ADRs in /Users/me/.claude/adr-registry:
  consumer-portal               (3 ADRs)
      IR-36-ADR-002-defer-pii-until-consent-accepted.md
      MYYES-17097-ADR-001-use-postgresql-circuit-breaker.md
      NOTICKET-ADR-003-adopt-pessimistic-write-lock-for-circuit-open.md
  leads-service                 (1 ADRs)
      NOTICKET-ADR-001-use-shlink-for-url-shortening.md

Use /adr-query to ask questions across this registry.
```

The list is sorted alphabetically, so ADRs group by ticket prefix — all `IR-*` files together, all `MYYES-*` together, etc. `NOTICKET-*` entries sort last by convention.

After listing, exit. Do not proceed to the publish steps below.

---

## Publish Mode (default)

| Step | Action |
|------|--------|
| 1 | Verifies `docs/adr/` exists and contains at least one `*.md` file |
| 2 | Detects the service name from `docs/service-info.md` (or git repo name) |
| 3 | Clears `~/.claude/adr-registry/<service-name>/` and copies every ADR into it |
| 4 | Prints confirmation listing the synced ADRs |

---

## Step 1 — Check Source Exists

```bash
[ -d docs/adr ] && find docs/adr -maxdepth 1 -name "*.md" -type f | head -1 | grep -q .
```

If `docs/adr/` does not exist, or contains no `*.md` files, abort:

```
docs/adr/ contains no ADR files.
Run /doc-adr first to create an ADR.
```

---

## Step 2 — Detect Service Name

Try in order:

1. Read the `# <ServiceName>` heading from `docs/service-info.md` — use the first `#` line, convert to kebab-case (strip a leading `Service:` prefix if present).
2. Fall back to the git repo name:
   ```bash
   git rev-parse --show-toplevel | xargs basename
   ```

Example: heading `# Service: consumer-portal` → `consumer-portal`.

---

## Step 3 — Sync

The sync is **clear-and-copy** — the registry subdir is rewritten to exactly match the source. This drops any stale ADRs that were renamed or removed in the repo.

```bash
SERVICE="<service-name>"
REGISTRY="${CLAUDE_DOC_HOME:-$HOME/.claude}/adr-registry"
DEST="$REGISTRY/$SERVICE"

mkdir -p "$REGISTRY"
rm -rf "$DEST"
mkdir -p "$DEST"
cp docs/adr/*.md "$DEST"/
```

The `rm -rf` is scoped to the **service's own subdir** — it never touches other services' ADRs.

---

## Step 4 — Confirm

After the copy succeeds, list every ADR now in the service subdir. Use this command:

```bash
ls -1 "${CLAUDE_DOC_HOME:-$HOME/.claude}/adr-registry/<service-name>"/*.md 2>/dev/null | xargs -n1 basename | sort
```

Then print the confirmation block, substituting the real names:

```text
Published <N> ADRs from docs/adr/ → ~/.claude/adr-registry/<service-name>/

Synced:
  IR-36-ADR-002-defer-pii-until-consent-accepted.md
  MYYES-17097-ADR-001-use-postgresql-circuit-breaker.md
  NOTICKET-ADR-003-adopt-pessimistic-write-lock-for-circuit-open.md

Run /adr-query to ask questions across the registry.
```

Always print the full file list — never abbreviate to a count and never elide entries with "...". The user needs the explicit file names to know what is now queryable.

---

## Related Skills

- `doc-adr` — creates an ADR file under `docs/adr/`
- `adr-query` — reads every ADR in `~/.claude/adr-registry/` and answers cross-service decision questions
- `doc-publish` — same pattern for service catalogs (`docs/service-info.md`)
