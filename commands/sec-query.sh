#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/service-catalog"
LOCAL_DOCS="$(pwd)/docs/security"

# --- collect security docs ---------------------------------------------------

FILES=()

# Try registry first, fall back to local
if [ -d "$REGISTRY/docs" ]; then
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find "$REGISTRY/docs" -path '*/security/*.md' -type f 2>/dev/null)
fi

if [ ${#FILES[@]} -eq 0 ]; then
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find "$LOCAL_DOCS" -name '*.md' -type f 2>/dev/null)
fi

# Also pick up any gl-*-report*.md or security-report.md at root docs/ level
if [ ${#FILES[@]} -eq 0 ]; then
  for name in security-report.md; do
    [ -f "docs/$name" ] && FILES+=("$(pwd)/docs/$name")
  done
  # Also include raw JSON reports if present (mark them as raw data)
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find docs -name 'gl-*-report*.json' -type f 2>/dev/null | head -5)
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No security docs found."
  echo ""
  echo "Checked:"
  echo "  Registry: $REGISTRY/docs/*/security/*.md"
  echo "  Local:    $LOCAL_DOCS/"
  echo "  Local:    docs/security-report.md"
  echo ""
  echo "Run /doc-publish --with-docs to publish security docs to the registry."
  exit 0
fi

echo "Reading ${#FILES[@]} security documents:"
for f in "${FILES[@]}"; do
  rel="${f#${REGISTRY}/}"
  rel="${rel#$(pwd)/}"
  echo "  $rel"
done
echo ""

for f in "${FILES[@]}"; do
  rel="${f#${REGISTRY}/}"
  rel="${rel#$(pwd)/}"
  echo "========================================"
  echo "FILE: $rel"
  echo "========================================"
  # For JSON files, note they're raw data
  if [[ "$f" == *.json ]]; then
    echo "(raw JSON report — parse as structured data)"
  fi
  cat "$f"
  echo ""
done

echo ""
echo "---"
echo "Question: ${1:-}"
echo "Use the security docs above to answer. Cite the source file for every claim."
echo "Focus on CVEs, findings, accepted risks, and security posture."
