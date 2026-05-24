#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/gates.sh"

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }
fmt_bold() { printf '\033[1m%s\033[0m\n' "$1"; }

# ---- detect glab ------------------------------------------------------------

GLAB_AVAILABLE=false
if command -v glab &>/dev/null; then
  GLAB_AVAILABLE=true
fi

# ---- resolve context --------------------------------------------------------

SLUG=$(resolve_slug 2>/dev/null || echo "")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

MR_URL=""
MR_IID=""

if [ -n "$SLUG" ]; then
  STATE_FILE=".specwork/_state/${SLUG}-state.json"
  if [ -f "$STATE_FILE" ]; then
    PY_SCRIPT=$(mktemp)
    cat > "$PY_SCRIPT" <<'PYEOF'
import json, sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")).get("mr_url", ""))
PYEOF
    MR_URL=$(python3 "$PY_SCRIPT" "$STATE_FILE" 2>/dev/null || echo "")
    rm -f "$PY_SCRIPT"
  fi
fi

if [ -n "$MR_URL" ]; then
  MR_IID=$(echo "$MR_URL" | grep -oE '[0-9]+$' || echo "")
fi

echo "Branch: $BRANCH"
echo "Slug:   ${SLUG:-"(none)"}"
echo "glab:   $([ "$GLAB_AVAILABLE" = true ] && echo 'available' || echo 'not available')"
[ -n "$MR_IID" ] && echo "MR:     !$MR_IID"
echo ""

# ---- load or create progress file -------------------------------------------

REVIEW_DIR=".specwork/_review"
mkdir -p "$REVIEW_DIR"
PROGRESS_FILE="${REVIEW_DIR}/${SLUG}-review-address.md"

if [ ! -f "$PROGRESS_FILE" ]; then
  cat > "$PROGRESS_FILE" <<EOF
# Review Address: ${SLUG}

MR: ${MR_IID:+"!${MR_IID}"}${MR_IID:-"(unknown)"}

## Addressed

## Deferred
EOF
fi

# ---- collect threads --------------------------------------------------------

THREADS=""

if [ "$GLAB_AVAILABLE" = true ] && [ -n "$MR_IID" ]; then
  echo "Fetching unresolved threads from MR !$MR_IID ..."
  THREADS=$(glab mr notes "$MR_IID" 2>/dev/null || true)
  if [ -z "$THREADS" ]; then
    echo "No threads fetched via glab."
    echo ""
  fi
fi

if [ -z "$THREADS" ]; then
  echo "No glab data available. Paste a review comment below, or use 'done' to stop."
  echo ""
  MODE="manual"
else
  MODE="auto"
fi

# ---- print instructions -----------------------------------------------------

ALREADY_ADDRESSED=$(grep '^- \[x\]' "$PROGRESS_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
ALREADY_DEFERRED=$(grep '^- \[ \]' "$PROGRESS_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo "0")

echo "==================================================="
echo " REVIEW ADDRESS SESSION"
echo "==================================================="
echo ""
fmt_bold "Progress file: $PROGRESS_FILE"
echo "  Already addressed: $ALREADY_ADDRESSED"
echo "  Deferred:          $ALREADY_DEFERRED"
echo ""

if [ "$MODE" = "auto" ]; then
  echo "Using glab. Handling unresolved threads one by one."
else
  echo "Manual mode. Paste one comment at a time."
  echo "Format includes optional file: and line: hints."
fi

cat <<INSTRUCTIONS

===================================================
 PER-THREAD INSTRUCTIONS
===================================================

For each thread, show:
  - author
  - file/line (if available)
  - comment text
  - actions: fix / reply / defer / skip / done

Actions:
  fix    — make the code change, show a minimal diff, confirm
  reply  — compose a reply and post it (or print it for manual paste)
  defer  — mark as pending in the progress file
  skip   — move on without recording
  done   — stop the session

Update ${PROGRESS_FILE} after each thread:

  ## Addressed
  - [x] <discussion-id>: @author — fixed|replied

  ## Deferred
  - [ ] <discussion-id>: @author

Read only the file or lines needed for the current thread.
Keep context minimal per thread.

===================================================
 END OF SESSION
===================================================

After all threads:
  1. Print a summary (fixed / replied / deferred / skipped)
  2. If files changed, offer to commit and optionally push

INSTRUCTIONS
