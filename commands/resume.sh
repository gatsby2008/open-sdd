#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/gates.sh"
source "$LIB_DIR/non_interactive.sh"
hydrate_non_interactive_from_state "$(resolve_slug 2>/dev/null || true)"

# ---- helpers ----------------------------------------------------------------

die() { echo "$*" >&2; exit 1; }
fmt_bold() { printf '\033[1m%s\033[0m\n' "$1"; }

# ---- step 1: find pipeline stashes ------------------------------------------

# Filtering + dedup live in the engine (stash-list = newest per branch; stash-stale
# = older duplicates). Both emit "<ref>\t<branch>".
KEPT=$(PYTHONPATH="$SCRIPT_DIR/.." python3 -m engine.cli stash-list 2>/dev/null)

if [ -z "$KEPT" ]; then
  die "No paused pipeline branches found.

To pause a pipeline branch, run /f-pause while on the branch that
owns the current .specwork state."
fi

# ---- step 2: parse stashes into array ---------------------------------------

declare -A DUP_REFS_FOR
STASH_REFS=()
STASH_BRANCHES=()
DUP_COUNT=0

while IFS=$'\t' read -r ref branch; do
  [ -n "$ref" ] || continue
  STASH_REFS+=("$ref")
  STASH_BRANCHES+=("$branch")
  DUP_REFS_FOR[$branch]=""
done <<< "$KEPT"

while IFS=$'\t' read -r ref branch; do
  [ -n "$ref" ] || continue
  DUP_COUNT=$((DUP_COUNT + 1))
  DUP_REFS_FOR[$branch]="${DUP_REFS_FOR[$branch]:-} $ref"
done <<< "$(PYTHONPATH="$SCRIPT_DIR/.." python3 -m engine.cli stash-stale 2>/dev/null)"

TOTAL=${#STASH_REFS[@]}

if [ "$DUP_COUNT" -gt 0 ]; then
  echo "  ($DUP_COUNT older stash${DUP_COUNT:+es} for the same branch${DUP_COUNT:+es} — using the most recent only)" >&2
  echo "" >&2
fi

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
  echo "  ($OTHER_COUNT other stash${OTHER_COUNT:+es} exist but have no pipeline context — use 'git stash list' to see them)"
fi

echo ""

if [ "$TOTAL" -eq 1 ]; then
  if [ "${SDD_NON_INTERACTIVE:-0}" = "1" ]; then
    echo "Non-interactive: resuming ${STASH_BRANCHES[0]}."
    SELECTED=0
  else
    echo "Resume ${STASH_BRANCHES[0]}? (y/n)"
    read -r choice
    case "$choice" in
      y|Y|yes|Yes) SELECTED=0 ;;
      *) echo "Aborted."; exit 1 ;;
    esac
  fi
else
  if [ "${SDD_NON_INTERACTIVE:-0}" = "1" ]; then
    die "Multiple paused branches — cannot auto-select in non-interactive mode."
  fi
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

Commit, stash, or discard them first, then run /f-resume again."
fi

# ---- step 6: switch to branch and pop stash ---------------------------------

fmt_bold "Switching to $SELECTED_BRANCH ..."

# Try to switch (create locally if the branch doesn't exist yet)
git switch "$SELECTED_BRANCH" 2>/dev/null || git switch -c "$SELECTED_BRANCH" 2>/dev/null || {
  die "Could not switch to branch '$SELECTED_BRANCH'."
}

fmt_bold "Restoring work from stash ..."
git stash pop "$SELECTED_REF"

# /f-pause force-adds the gitignored .specwork/ into the stash so the pipeline
# state survives. On pop, git restores those files to the INDEX (staged) because
# they don't exist in HEAD — so .specwork/ comes back staged, which must never
# happen (it's transient, gitignored state). Unstage it: the files stay in the
# working tree and return to their proper ignored status.
if [ -d ".specwork" ]; then
  git reset -q -- .specwork/ 2>/dev/null || true
fi

# ---- step 7: drop stale duplicate stashes for the resumed branch ----------

dups="${DUP_REFS_FOR[$SELECTED_BRANCH]:-}"
if [ -n "$dups" ]; then
  for ref in $dups; do
    echo "  Dropping stale duplicate stash $ref ..."
    git stash drop "$ref" 2>/dev/null || true
  done
fi

echo ""
echo "Resumed $SELECTED_BRANCH."
echo ""
echo "Run /f-status to see where you left off."
echo "Run /f-implement to continue."
