#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/service-catalog"
LOCAL_DOCS="$(pwd)/docs/product"

# --- collect spec docs -------------------------------------------------------

FILES=()

# Try registry first, fall back to local
if [ -d "$REGISTRY/docs" ]; then
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find "$REGISTRY/docs" -path '*/product/*.md' -type f 2>/dev/null)
fi

if [ ${#FILES[@]} -eq 0 ] && [ -d "$LOCAL_DOCS" ]; then
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find "$LOCAL_DOCS" -name '*.md' -type f 2>/dev/null)
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No product specs found."
  echo ""
  echo "Checked:"
  echo "  Registry: $REGISTRY/docs/*/product/*.md"
  echo "  Local:    $LOCAL_DOCS/*.md"
  echo ""
  echo "Run /doc-publish --with-docs in each service to publish product specs."
  exit 0
fi

echo "Reading ${#FILES[@]} product spec documents:"
for f in "${FILES[@]}"; do
  rel="${f#${REGISTRY}/}"
  rel="${rel#${LOCAL_DOCS}/}"
  echo "  $rel"
done
echo ""

for f in "${FILES[@]}"; do
  rel="${f#${REGISTRY}/}"
  rel="${rel#${LOCAL_DOCS}/}"
  echo "========================================"
  echo "FILE: $rel"
  echo "========================================"
  cat "$f"
  echo ""
done

echo ""
echo "---"
echo "Question: ${1:-}"
echo "Use the product specs above to answer. Cite the source file for every claim."
echo "Focus on user stories, gaps, features, and personas."
