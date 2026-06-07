#!/usr/bin/env bash
# /spec-query — print every published spec so the model can answer feature/spec
# questions across services. Reads the registry that lib/spec-publish.sh writes
# (populated by /f-mr): $OPEN_SDD_DOC_HOME/spec-registry/<service>/<slug>-spec.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Same registry root as doc-query/adr-query and lib/spec-publish.sh, so we read
# exactly what /f-mr wrote.
REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/spec-registry"

FILES=()
while IFS= read -r f; do
  FILES+=("$f")
done < <(find "$REGISTRY" -name '*-spec.md' -type f 2>/dev/null)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No specs found in $REGISTRY/"
  echo ""
  echo "Publish a spec with /spec-publish <path>, or run the pipeline through /f-mr"
  echo "(which publishes automatically when a .specwork spec exists), then re-run this query."
  exit 0
fi

echo "Reading ${#FILES[@]} spec(s):"
for f in "${FILES[@]}"; do
  echo "  ${f#"$REGISTRY"/}"
done
echo ""

for f in "${FILES[@]}"; do
  echo "========================================"
  echo "FILE: ${f#"$REGISTRY"/}"
  echo "========================================"
  cat "$f"
  echo ""
done

echo ""
echo "---"
echo "Question: ${1:-}"
echo "Use the specs above (Summary, Behavior, Scope, Implementation Context, Safe"
echo "Constraints, Open Questions) to answer the question. Cite every claim as"
echo "<service>/<spec-file>."
