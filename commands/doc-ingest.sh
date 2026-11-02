#!/usr/bin/env bash
# /doc-ingest — compile the append-only raw/ registries into the compiled wiki/
# knowledge layer (raw -> wiki, the two-layer Karpathy model).
#
# The doc-* commands write raw/; this is the missing producer that weaves it
# into the [[backlinked]] wiki that /doc-ask navigates. Only applies where the
# registry root is the raw/ half of a two-layer vault (a wiki/ sibling).
#
# Modes:
#   doc-ingest [<path under raw/>]   compile that source
#   doc-ingest session               distill the current session into the wiki
#   doc-ingest                       auto: whatever in raw/ is newer than the last ingest
#   doc-ingest list                  show the vault layout and what is un-ingested (no writes)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RAW="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}"
VAULT="$(dirname "$RAW")"
WIKI="$VAULT/wiki"

# ---- argument parsing ---------------------------------------------------------

LIST_MODE=false
TARGET=""
for arg in "$@"; do
  case "$arg" in
    list) LIST_MODE=true ;;
    *) TARGET="$arg" ;;
  esac
done

# ---- vault check --------------------------------------------------------------

if [ ! -d "$WIKI" ]; then
  echo "No wiki layer found next to $RAW."
  echo ""
  echo "/doc-ingest compiles raw/ into a wiki/ knowledge layer — it needs a"
  echo "two-layer vault (a wiki/ sibling of raw/, per the Karpathy model)."
  echo "Nothing to do here."
  echo ""
  echo "To adopt one, create $WIKI with wiki.md, log.md, entities/, concepts/"
  echo "and sources/, then re-run /doc-ingest. /doc-ask keeps working on raw/ alone."
  exit 0
fi

# ---- vault layout + un-ingested sources (engine/ingest.py) ---------------------

ARGS=("$RAW")
if [ -n "$TARGET" ]; then ARGS+=("$TARGET"); fi

status="$(PYTHONPATH="$SCRIPT_DIR/.." python3 -m engine.cli ingest-status "${ARGS[@]}")" || exit 1
printf '%s\n' "$status"

# ---- list mode: facts only, no instructions -----------------------------------

if [ "$LIST_MODE" = true ]; then
  exit 0
fi

# ---- nothing to do: the wiki already covers raw/ ------------------------------

if [ -z "$TARGET" ] && printf '%s' "$status" | grep -qF "the wiki already covers every raw doc"; then
  echo ""
  echo "Nothing to compile: raw/ is fully ingested. Pass a path under $RAW,"
  echo "run '/doc-ingest session', or query the wiki with /doc-ask."
  exit 0
fi

# ---- instructions -------------------------------------------------------------

echo ""
echo "---"
echo "Instructions:"
echo ""
echo "1. Read the vault schema first — it is authoritative and can co-evolve"
echo "   without this command changing:"
if [ -f "$VAULT/CLAUDE.md" ]; then
  echo "     $VAULT/CLAUDE.md"
elif [ -f "$VAULT/AGENTS.md" ]; then
  echo "     $VAULT/AGENTS.md"
else
  echo "     (no CLAUDE.md/AGENTS.md at the vault root — follow the conventions"
  echo "      already used by the pages under $WIKI)"
fi
echo "   It owns the page frontmatter (type/subtype/tags), the H1 title, the"
echo "   ## Source section, the navigation files (wiki.md, folder-notes, log.md)"
echo "   and the Compile/Lint/Log operations. If schema and this command ever"
echo "   disagree, the schema wins."
echo ""
echo "2. Compile each selected source:"
echo "   - Read the raw file; extract the entities and concepts it introduces."
echo "   - Create or UPDATE IN PLACE the page under $WIKI/entities/<subtype> or"
echo "     $WIKI/concepts/<subtype> — grep before writing, never duplicate a page:"
echo "       grep -rli \"<entity or concept>\" \"$WIKI/entities\" \"$WIKI/concepts\""
echo "   - Write it in your own words (never copy raw/ verbatim), with the schema's"
echo "     frontmatter, [[wikilinks]] to related pages, and a ## Source section"
echo "     linking back to the raw/ file(s)."
echo "   - Prefer a few files per pass over one giant compile."
echo ""
echo "3. Update the affected indexes: entities.md, concepts.md, sources.md and"
echo "   $WIKI/wiki.md."
echo ""
echo "4. Append one entry to $WIKI/log.md in the schema's format:"
echo "     ## [$(date '+%Y-%m-%d')] compile | <title>"
echo "   (use 'ingest' instead of 'compile' for session mode), listing the pages"
echo "   created vs. updated. /doc-ask uses the newest date there as its watermark."
echo ""
echo "5. Verify 0 broken links — every [[wikilink]] must resolve to an existing"
echo "   page (create the missing target or fix the name). Do not finish with"
echo "   dangling links."
echo ""
echo "6. Report pages created vs. updated and the log line appended, e.g.:"
echo "     Compiled raw/service-catalog/leads-service.md -> wiki/"
echo "       Created (3):  entities/leads-service, concepts/lead-dedupe, concepts/savings-id-pool"
echo "       Updated (1):  entities/consumer-portal (now notes it owns the consent spine)"
echo "       Indexes:      entities.md, concepts.md, wiki.md · log.md appended · 0 broken links"
echo ""
echo "Rules:"
echo "  - Never hand-edit or delete files under $RAW — raw/ is append-only and the"
echo "    source of truth. This command writes only $WIKI."
echo "  - Distill reusable entities/concepts only; skip narrative and project-log"
echo "    material."
echo "  - Keep subtypes within the schema's controlled vocabulary so [[links]]"
echo "    resolve."
echo ""
echo "Then re-run /doc-ask — it reads the wiki's [[backlinks]] and its"
echo "\"wiki is behind\" warning clears once the log has a newer entry."
