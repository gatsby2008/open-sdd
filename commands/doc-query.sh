#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/service-catalog"

CATALOGS=("$REGISTRY"/*.md 2>/dev/null)
if [ ${#CATALOGS[@]} -eq 0 ] || [ ! -f "${CATALOGS[0]}" ]; then
  echo "No service catalogs found in $REGISTRY/"
  echo ""
  echo "Run /doc-catalog in each service project, then /doc-publish to register it."
  exit 0
fi

COUNT=${#CATALOGS[@]}
echo "Reading $COUNT service catalogs:"
for f in "${CATALOGS[@]}"; do
  echo "  $(basename "$f")"
done
echo ""

for f in "${CATALOGS[@]}"; do
  echo "========================================"
  echo "FILE: $(basename "$f")"
  echo "========================================"
  cat "$f"
  echo ""
done

echo ""
echo "---"
echo "Question: ${1:-}"
echo "Use the catalog contents above to answer the question."
echo "Cite the source catalog file for every claim."
