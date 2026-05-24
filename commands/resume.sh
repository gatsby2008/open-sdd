#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/gates.sh"

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }
fmt_bold() { printf '\033[1m%s\033[0m\n' "$1"; }

# ---- step 1: find pipeline stashes ------------------------------------------

STASHES=$(git stash list --format="%gd %s" 2>/dev/null | grep "f-pause:" || true)

if [ -z "$STASHES" ]; then
  die "No paused pipeline branches found.

To pause a pipeline branch, run ./commands/pause.sh while on the branch that
owns the current .specwork state."
fi

# ---- step 2: parse stashes into array ---------------------------------------

STASH_REFS=()
STASH_BRANCHES=()

while IFS= read -r line; do
  ref=${line%% *}
  branch=${line#*f-pause: }
  STASH_REFS+=("$ref")
  STASH_BRANCHES+=("$branch")
done <<< "$STASHES"

TOTAL=${#STASH_REFS[@]}

# ---- step 3: detect non-pipeline stashes ------------------------------------

ALL_COUNT=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
OTHER_COUNT=$((ALL_COUNT - TOTAL))
[ "$OTHER_COUNT" -lt 0 ] && OTHER_COUNT=0

# ---- step 4: show menu ------------------------------------------------------

echo "Paused pipeline branches:"
echo ""

for i in "${!STASH_REFS[@]}"; do
  echo "  [$i]  ${STASH_BRANCHES[$i]}"
done

if [ "$OTHER_COUNT" -gt 0 ]; then
  echo ""
  echo "  ($OTHER_COUNT other stash${OTHER_COUNT: +es} exist but have no pipeline context — use 'git stash list' to see them)"
fi

echo ""

if [ "$TOTAL" -eq 1 ]; then
  echo "Resume ${STASH_BRANCHES[0]}? (y/n)"
  read -r choice
  case "$choice" in
    y|Y|yes|Yes) SELECTED=0 ;;
    *) echo "Aborted."; exit 1 ;;
  esac
else
  printf "Resume which branch? (0-%d / cancel): " $((TOTAL - 1))
  read -r choice
  [ "$choice" = "cancel" ] && echo "Aborted." && exit 1
  SELECTED="$choice"
  if ! [[ "$SELECTED" =~ ^[0-9]+$ ]] || [ "$SELECTED" -ge "$TOTAL" ]; then
    die "Invalid selection."
  fi
fi

SELECTED_REF="${STASH_REFS[$SELECTED]}"
SELECTED_BRANCH="${STASH_BRANCHES[$SELECTED]}"

# ---- step 5: verify current working tree is clean ---------------------------

TREE=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$TREE" -gt 0 ]; then
  die "Cannot resume while the current working tree has changes.

Commit, stash, or discard them first, then run ./commands/resume.sh again."
fi

# ---- step 6: switch to branch and pop stash ---------------------------------

fmt_bold "Switching to $SELECTED_BRANCH ..."

# Try to switch (create locally if the branch doesn't exist yet)
git switch "$SELECTED_BRANCH" 2>/dev/null || git switch -c "$SELECTED_BRANCH" 2>/dev/null || {
  die "Could not switch to branch '$SELECTED_BRANCH'."
}

fmt_bold "Restoring work from stash ..."
git stash pop "$SELECTED_REF"

echo ""
echo "Resumed $SELECTED_BRANCH."
echo ""
echo "Run ./commands/status.sh to see where you left off."
echo "Run ./commands/implement.sh to continue."
