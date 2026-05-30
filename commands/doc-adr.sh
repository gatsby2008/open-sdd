#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "$*" >&2; exit 1; }

# ---- helpers ----------------------------------------------------------------

NEXT_ADR=1
if [ -d docs/adr ]; then
  LAST=$(find docs/adr -name "*-ADR-[0-9][0-9][0-9]-*.md" 2>/dev/null \
    | grep -oE 'ADR-[0-9]{3}' \
    | sort \
    | tail -1 \
    | grep -oE '[0-9]+' || echo "0")
  NEXT_ADR=$((10#$LAST + 1))
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
TICKET=""
if echo "$BRANCH" | grep -qE '^[a-zA-Z]+/[A-Z]+-[0-9]+'; then
  TICKET=$(echo "$BRANCH" | sed -E 's|^[a-zA-Z]+/([A-Z]+-[0-9]+).*|\1|')
elif echo "$BRANCH" | grep -qE '^[A-Z]+-[0-9]+'; then
  TICKET=$(echo "$BRANCH" | grep -oE '^[A-Z]+-[0-9]+')
fi

ARG="${1:-}"

echo "Next ADR number: ADR-$(printf '%03d' "$NEXT_ADR")"
echo "Branch: $BRANCH"
[ -n "$TICKET" ] && echo "Ticket: $TICKET"
echo ""

if [ "$ARG" = "open-questions" ]; then
  SPEC_DIR=".specwork/_spec"
  if [ -d "$SPEC_DIR" ]; then
    echo "Open Questions mode. Scanning resolved items..."
    for f in "$SPEC_DIR"/*-spec.md; do
      [ -f "$f" ] || continue
      echo "--- Spec: $(basename "$f") ---"
      grep -E '^\s*(- \[x\]|- \[X\])' "$f" 2>/dev/null || echo "(no resolved questions)"
    done
  else
    echo "No .specwork/_spec/ found. Run /f-start first."
  fi
elif echo "$ARG" | grep -qE '^[A-Z]+-[0-9]+$'; then
  echo "Jira mode. To capture decisions from ticket $ARG, ask the user for context."
elif [ -n "$ARG" ]; then
  echo "Description: $ARG"
fi

echo ""
echo "---"
echo "Existing ADRs in docs/adr/:"
if [ -d docs/adr ]; then
  ls -1 docs/adr/*ADR-*.md 2>/dev/null | sort || echo "(none)"
else
  echo "(none — docs/adr/ does not exist)"
fi

echo ""
echo "ADR-NNN format:"
echo "  <TICKET>-ADR-NNN-<kebab-slug>.md"
echo ""
echo "Use this info to draft the ADR, confirm with the user,"
echo "then write the file to docs/adr/ and offer to commit."
