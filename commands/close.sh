#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/gates.sh"

# ---- state ------------------------------------------------------------------

SLUG=""
STATE_FILE=""

die() { echo "$*" >&2; exit 1; }
fmt_bold() { printf '\033[1m%s\033[0m\n' "$1"; }

# ---- resolve slug -----------------------------------------------------------

SLUG=$(resolve_slug) || die "Could not resolve slug."
STATE_FILE=".specwork/_state/${SLUG}-state.json"

# ---- check MR merge status --------------------------------------------------

MR_URL=""
if [ -f "$STATE_FILE" ]; then
  MR_URL=$(python3 - "$STATE_FILE" 2>/dev/null <<'PY' || true
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(data.get("mr_url", ""))
PY
)
fi

if [ -n "$MR_URL" ]; then
  echo "Checking MR status..."
  if command -v gh &>/dev/null; then
    MR_NUM=$(echo "$MR_URL" | grep -oE '[0-9]+$' || true)
    if [ -n "$MR_NUM" ]; then
      MR_STATE=$(gh pr view "$MR_NUM" --json state,merged --jq '.state' 2>/dev/null || echo "")
      MR_MERGED=$(gh pr view "$MR_NUM" --json merged --jq '.merged' 2>/dev/null || echo "false")

      if [ "$MR_STATE" = "MERGED" ] || [ "$MR_MERGED" = "true" ]; then
        echo "MR is merged. Proceeding with close."
      elif [ "$MR_STATE" = "CLOSED" ]; then
        echo "MR is closed (not merged)."
        echo ""
        echo "  c) Delete .specwork anyway"
        echo "  q) Quit and investigate"
        read -r choice
        case "$choice" in
          c|C) echo "Proceeding..." ;;
          *) exit 1 ;;
        esac
      else
        echo "MR #$MR_NUM is still open ($MR_STATE)."
        echo ""
        echo "Are you sure you want to close the feature pipeline? [y/N]"
        read -r choice
        if [ "$choice" != "y" ] && [ "$choice" != "Y" ]; then
          echo "Aborted."
          exit 1
        fi
      fi
    fi
  else
    echo "gh not installed. Cannot verify MR status."
    echo ""
    echo "  y) Delete .specwork anyway"
    echo "  n) Abort"
    read -r choice
    case "$choice" in
      y|Y) echo "Proceeding..." ;;
      *) exit 1 ;;
    esac
  fi
else
  echo "No MR URL found in state."
  echo ""
  echo "  y) Delete .specwork anyway"
  echo "  n) Abort"
  read -r choice
  case "$choice" in
    y|Y) echo "Proceeding..." ;;
    *) exit 1 ;;
  esac
fi

# ---- delete .specwork/ ------------------------------------------------------

echo ""
fmt_bold "Deleting .specwork/ ..."
rm -rf .specwork/
echo "Done. .specwork/ removed."

# ---- offer branch cleanup ---------------------------------------------------

BRANCH=$(git rev-parse --abbrev-ref HEAD)
DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep "HEAD branch" | awk '{print $NF}' || echo "main")

if [ "$BRANCH" != "$DEFAULT_BRANCH" ]; then
  echo ""
  echo "You are on feature branch '$BRANCH'."
  echo ""
  echo "  d) Delete local branch and switch to $DEFAULT_BRANCH"
  echo "  k) Keep branch, switch to $DEFAULT_BRANCH"
  echo "  s) Stay on branch"
  echo "  q) Quit"
  read -r choice
  case "$choice" in
    d|D)
      git checkout "$DEFAULT_BRANCH"
      git branch -D "$BRANCH"
      echo "Branch '$BRANCH' deleted. Switched to $DEFAULT_BRANCH."
      ;;
    k|K)
      git checkout "$DEFAULT_BRANCH"
      echo "Switched to $DEFAULT_BRANCH. Branch '$BRANCH' preserved."
      ;;
    s|S)
      echo "Staying on branch '$BRANCH'."
      ;;
    *)
      echo "Aborted."
      exit 1
      ;;
  esac
fi

echo ""
echo "Feature pipeline closed."
