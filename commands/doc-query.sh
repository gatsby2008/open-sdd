#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/service-catalog"

# ---- collect all markdown files (catalogs + extra docs) -----------------------

FILES=()
while IFS= read -r f; do
  FILES+=("$f")
done < <(find "$REGISTRY" -name '*.md' -type f 2>/dev/null)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No service catalogs found in $REGISTRY/"
  echo ""
  echo "Run /doc-catalog in each service project, then /doc-publish to register it."
  exit 0
fi

echo "Reading ${#FILES[@]} documents:"
for f in "${FILES[@]}"; do
  rel="${f#$REGISTRY/}"
  echo "  $rel"
done
echo ""

for f in "${FILES[@]}"; do
  rel="${f#$REGISTRY/}"
  echo "========================================"
  echo "FILE: $rel"
  echo "========================================"
  cat "$f"
  echo ""
done

echo ""
echo "---"
echo "Question: ${1:-}"
echo "Use the documents above to answer the question."
echo "Cite the source file (relative to registry) for every claim."
