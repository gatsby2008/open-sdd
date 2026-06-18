#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
# shellcheck source=../lib/service-name.sh
. "$LIB_DIR/service-name.sh"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/adr-registry"

# ---- parse arguments ---------------------------------------------------------

if [ "${1:-}" = "list" ]; then
  SERVICE_NAME="$(resolve_service_name)"
  ADR_DIR="$REGISTRY/$SERVICE_NAME"
  if [ -d "$ADR_DIR" ]; then
    count="$(ls -1 "$ADR_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$count" -gt 0 ]; then
      echo "ADRs for $SERVICE_NAME ($count total):"
      ls -1 "$ADR_DIR"/*.md 2>/dev/null | xargs -n1 basename | sort | sed 's/^/  /'
    else
      echo "No ADRs found for $SERVICE_NAME."
    fi
  else
    echo "No ADRs found for $SERVICE_NAME."
    echo "Run /doc-adr in this repo to create and publish one."
  fi
  exit 0
fi

# ---- detect service ----------------------------------------------------------

SERVICE_NAME="$(resolve_service_name)"

# ---- helpers ----------------------------------------------------------------

# ADR numbering is service-wide and monotonic, scoped to the registry subdir
# (registry is the single home — there is no in-repo docs/adr/).
ADR_DIR="$REGISTRY/$SERVICE_NAME"
NEXT_ADR=1
if [ -d "$ADR_DIR" ]; then
  LAST=$(find "$ADR_DIR" -name "*-ADR-[0-9][0-9][0-9]-*.md" 2>/dev/null \
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

echo "Service: $SERVICE_NAME"
echo "Next ADR number: ADR-$(printf '%03d' "$NEXT_ADR")"
echo "Branch: $BRANCH"
[ -n "$TICKET" ] && echo "Ticket: $TICKET"
echo ""

if [ "$ARG" = "open-questions" ]; then
  FOUND=false
  if [ -d ".specwork/_spec" ]; then
    echo "== Pipeline specs =="
    for f in ".specwork/_spec"/*-spec.md; do
      [ -f "$f" ] || continue
      FOUND=true
      echo "--- Spec: $(basename "$f") ---"
      grep -E '^\s*(- \[x\]|- \[X\])' "$f" 2>/dev/null || echo "(no resolved questions)"
    done
  fi
  for f in docs/decisions.md docs/open-questions.md docs/adr/decisions.md; do
    [ -f "$f" ] || continue
    FOUND=true
    echo "--- $(basename "$f") ---"
    grep -E '^\s*(- \[x\]|- \[X\]|## Resolved|## Decision|## OQ[0-9]|^### .*resolved)' "$f" 2>/dev/null | head -30 || true
  done
  if [ "$FOUND" = false ]; then
    echo "No specs or decisions files found. Provide context directly."
  fi
elif echo "$ARG" | grep -qE '^[A-Z]+-[0-9]+$'; then
  echo "Jira mode. To capture decisions from ticket $ARG, ask the user for context."
elif [ -n "$ARG" ]; then
  echo "Description: $ARG"
fi

echo ""
echo "Existing ADRs for $SERVICE_NAME in the registry:"
if [ -d "$ADR_DIR" ] && ls "$ADR_DIR"/*ADR-*.md >/dev/null 2>&1; then
  ls -1 "$ADR_DIR"/*ADR-*.md 2>/dev/null | xargs -n1 basename | sort
else
  echo "(none yet)"
fi

echo ""
echo "ADR-NNN format:"
echo "  <TICKET>-ADR-NNN-<kebab-slug>.md"
echo ""
echo "---"
echo "Instructions:"
echo ""
echo "1. Use the context above to draft the ADR."
echo "   Filename: ${TICKET:-NOTICKET}-ADR-$(printf '%03d' "$NEXT_ADR")-<kebab-slug>.md"
echo ""
echo "2. Write it STRAIGHT to the registry — no copy in the repo, no confirmation prompt:"
echo "   mkdir -p \"$REGISTRY/$SERVICE_NAME\""
echo "   # write the ADR to \"$REGISTRY/$SERVICE_NAME/<filename>.md\""
echo ""
echo "3. List the registry to confirm, and print the stored path:"
echo "   ls -1 \"$REGISTRY/$SERVICE_NAME/\"*.md 2>/dev/null | xargs -n1 basename | sort"
echo ""
echo "Run /doc-adr-query to ask questions across the registry."
