#!/usr/bin/env bash
# /doc-investigation — capture a session investigation as a structured document
# in the investigation-registry. Supports bug, exploration, and improvements types.
#
# Modes:
#   doc-investigation [title] [bug|explore|improvements]
#   doc-investigation list
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
TEMPLATES_DIR="$SCRIPT_DIR/../templates"
# shellcheck source=../lib/service-name.sh
. "$LIB_DIR/service-name.sh"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/investigation-registry"

# ---- list mode ----------------------------------------------------------------

if [ "${1:-}" = "list" ]; then
  SERVICE_NAME="$(resolve_service_name)"
  INV_DIR="$REGISTRY/$SERVICE_NAME"
  if [ -d "$INV_DIR" ]; then
    invs=("$INV_DIR"/*.md)
    if [ ${#invs[@]} -gt 0 ] && [ -f "${invs[0]}" ]; then
      echo "Investigations for $SERVICE_NAME:"
      for inv in "${invs[@]}"; do
        echo "  $(basename "$inv")"
      done
    else
      echo "No investigations found for $SERVICE_NAME."
    fi
  else
    echo "No investigations found for $SERVICE_NAME."
    echo "Run /doc-investigation in this repo to capture one."
  fi
  exit 0
fi

# ---- parse arguments ----------------------------------------------------------

TITLE=""
FORCE_TYPE=""
for arg in "$@"; do
  case "$arg" in
    bug|explore|exploration|improvements)
      FORCE_TYPE="$arg"
      ;;
    *)
      if [ -z "$TITLE" ]; then
        TITLE="$arg"
      else
        TITLE="$TITLE $arg"
      fi
      ;;
  esac
done

# ---- detect service -----------------------------------------------------------

SERVICE_NAME="$(resolve_service_name)"
echo "Service: $SERVICE_NAME"
echo ""

# ---- print templates and instructions -----------------------------------------

echo "Available investigation templates:"
echo ""
echo "  bug           — Problem → Symptoms → Root Cause → Fix"
echo "  exploration   — Question → Map → How It Works → Future Signals"
echo "  improvements  — Goal → Current State → Gap Analysis → Plan"
echo ""

TYPE="${FORCE_TYPE:-auto-detect}"

if [ "$TYPE" = "auto-detect" ]; then
  echo "Type: auto-detect (infer from session — pass 'bug', 'explore', or 'improvements' to force)"
  echo ""
  echo "Rules:"
  echo "  - bug:           the session chased a defect, error, or unexpected behavior."
  echo "  - exploration:   the session set out to understand a mechanism or flow."
  echo "  - improvements:  the session analyzed a gap between current state and a goal."
  echo "  When ambiguous, default to exploration."
fi

if [ "$TYPE" = "bug" ] || [ "$TYPE" = "auto-detect" ]; then
  echo ""
  echo "=== Bug template ==="
  cat "$TEMPLATES_DIR/investigation-bug.md"
fi

if [ "$TYPE" = "exploration" ] || [ "$TYPE" = "explore" ] || [ "$TYPE" = "auto-detect" ]; then
  echo ""
  echo "=== Exploration template ==="
  cat "$TEMPLATES_DIR/investigation-explore.md"
fi

if [ "$TYPE" = "improvements" ]; then
  echo ""
  echo "=== Improvements template ==="
  cat "$TEMPLATES_DIR/investigation-improvements.md"
fi

echo ""
echo "---"
echo "Instructions:"
echo ""
echo "1. Classify the investigation type ($TYPE)"
echo "   - If auto-detect, read the session and decide bug vs exploration."
echo "   - Pass 'improvements' to force the forward-looking improvements template."
echo "   - Announce the chosen type before drafting."
echo ""
echo "2. Fill the matching template from the session conversation."
echo "   - Source is the session only — do not re-investigate code."
echo "   - Quote code/sql verbatim as it appeared in the session."
echo "   - Mark gaps as [TBD], inferences as [INFERRED]."
if [ -n "$TITLE" ]; then
  echo "   - Title: $TITLE (use as the first H1 heading)"
fi
echo ""
echo "3. Print the full draft (type + destination path), then write it — no yes/no gate."
echo "   The type was already chosen, so proceed straight to the write; the user"
echo "   can still interrupt to edit if something is wrong."
echo ""
echo "4. Write STRAIGHT to: $REGISTRY/${SERVICE_NAME}/<date>-<slug>.md"
echo ""
echo "5. After writing, list the registry and print the stored path:"
echo "   ls -1 \"$REGISTRY/${SERVICE_NAME}/\"*.md 2>/dev/null | xargs -n1 basename | sort"
echo ""
echo "Cite every source as ${SERVICE_NAME}/<filename>."
