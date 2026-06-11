#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
TEMPLATES_DIR="$SCRIPT_DIR/../templates"
# shellcheck source=../lib/service-name.sh
. "$LIB_DIR/service-name.sh"

die() { echo "$*" >&2; exit 1; }

REGISTRY="${OPEN_SDD_DOC_HOME:-${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry}/investigation-registry"

# ---- parse arguments ----------------------------------------------------------

TITLE=""
FORCE_TYPE=""
for arg in "$@"; do
  case "$arg" in
    bug|explore|exploration)
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
echo "  bug          — Problem → Symptoms → Root Cause → Fix"
echo "  exploration  — Question → Map → How It Works → Future Signals"
echo ""

TYPE="${FORCE_TYPE:-auto-detect}"

if [ "$TYPE" = "auto-detect" ]; then
  echo "Type: auto-detect (infer from session — pass 'bug' or 'explore' to force)"
  echo ""
  echo "Rules:"
  echo "  - bug:        the session chased a defect, error, or unexpected behavior."
  echo "  - exploration: the session set out to understand a mechanism or flow."
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

echo ""
echo "---"
echo "Instructions:"
echo ""
echo "1. Classify the investigation type ($TYPE)"
echo "   - If auto-detect, read the session and decide bug vs exploration."
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
echo "3. Confirm with the user before writing."
echo "   - Print the full draft, type, and destination path."
echo "   - Offer: y / edit / type / cancel"
echo ""
echo "4. Write to: $REGISTRY/${SERVICE_NAME}/<date>-<slug>.md"
echo ""
echo "5. After writing, list the registry:"
echo "   ls -1 \"$REGISTRY/${SERVICE_NAME}/\"*.md 2>/dev/null | xargs -n1 basename | sort"
echo ""
echo "Cite every source as ${SERVICE_NAME}/<filename>."
